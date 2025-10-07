#!/usr/bin/env bats

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  source "$BATS_TEST_DIRNAME/../test_helper.bash"
  LAUNCH="$PROJECT_ROOT/src/server/launch_server.bash"
  SERVER_SCRIPT="$PROJECT_ROOT/src/server/canned_responses.bash"
}

_make_response() {
  local path="$1" body="$2"
  local len
  len=${#body}
  cat > "$path" <<EOF
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close
Content-Length: $len

$body
EOF
}

_launch_canned() {
  local responses_json="$1"; shift

  # Always use a standard directory for request logs within the test's temp dir.
  local request_dir="$BATS_TEST_TMPDIR/requests"
  mkdir -p "$request_dir"

  log_debug "responses_json $responses_json"

  readarray -t out < <(bash "$LAUNCH" --server_script "$SERVER_SCRIPT" --responses "$responses_json" --request-dir "$request_dir" --stdout_log "3" --stderr_log "3")
  PORT="${out[0]}"
  PID="${out[1]}"
  [ -n "$PORT" ] || fail "No port returned"
  [ -n "$PID" ] || fail "No PID returned"
  echo "Launched: port=$PORT pid=$PID responses=$responses_json" >&3
}

_wait_down() {
  local pid="$1"; for i in {1..50}; do if ! kill -0 "$pid" 2>/dev/null; then return 0; fi; sleep 0.05; done; return 1;
}

@test "multi responses served sequentially and logged" {
  enable_tracing
  resp1="$BATS_TEST_TMPDIR/r1.http"; resp2="$BATS_TEST_TMPDIR/r2.http"
  _make_response "$resp1" hello
  _make_response "$resp2" world
  responses_json=$(jq -nc --arg a "$resp1" --arg b "$resp2" '[$a,$b]')

  log_debug "responses_json $responses_json"

  # _launch_canned will handle creating the directory and passing it to the server.
  _launch_canned "$responses_json"
  
  # The test knows by convention where to find the logs.
  local REQ_DIR="$BATS_TEST_TMPDIR/requests"

  sleep 1
  curl --silent --show-error --fail http://127.0.0.1:"$PORT"/ > "$BATS_TEST_TMPDIR/body1" || fail "curl 1 failed"
  assert_equal "hello" "$(cat "$BATS_TEST_TMPDIR/body1")"
  log_debug "test got \"hello\" back"
  
  sleep 1
  curl --silent --show-error --fail http://127.0.0.1:"$PORT"/ > "$BATS_TEST_TMPDIR/body2" || fail "curl 2 failed"
  assert_equal "world" "$(cat "$BATS_TEST_TMPDIR/body2")"
  log_debug "got \"world\" back"
  
  _wait_down "$PID" || fail "Server still running after two responses"
  
  [ -f "$REQ_DIR/request.0.log" ] || fail "Missing request 0 log"
  [ -f "$REQ_DIR/request.1.log" ] || fail "Missing request 1 log"
  grep -q "hello" "$BATS_TEST_TMPDIR/body1" || fail "Body1 mismatch"
  grep -q "GET / HTTP" "$REQ_DIR/request.0.log" || fail "No GET in first log"
}

@test "single response then exit" {
  resp="$BATS_TEST_TMPDIR/only.http"
  _make_response "$resp" single
  responses_json=$(jq -n --arg p "$resp" '[$p]')
  _launch_canned "$responses_json"
  sleep 0.1
  curl --silent --show-error --fail http://127.0.0.1:"$PORT"/ > "$BATS_TEST_TMPDIR/single" || fail "curl failed"
  assert_equal single "$(cat "$BATS_TEST_TMPDIR/single")"
  _wait_down "$PID" || fail "Server still running after single response"
}

@test "third connection refused after two responses" {
  r1="$BATS_TEST_TMPDIR/a.http"; r2="$BATS_TEST_TMPDIR/b.http"
  _make_response "$r1" first
  _make_response "$r2" second
  responses_json=$(jq -n --arg a "$r1" --arg b "$r2" '[$a,$b]')
  _launch_canned "$responses_json"
  sleep 0.1
  curl --silent --fail http://127.0.0.1:"$PORT"/ > /dev/null || fail "1st curl failed"
  sleep 1
  curl --silent --fail http://127.0.0.1:"$PORT"/ > /dev/null || fail "2nd curl failed"
  # Third should fail
  if curl --silent --fail http://127.0.0.1:"$PORT"/ > /dev/null 2>&1; then
    fail "Third curl unexpectedly succeeded"
  fi
}

@test "explicit port honored" {
  resp="$BATS_TEST_TMPDIR/p.http"; _make_response "$resp" porttest
  responses_json=$(jq -n --arg p "$resp" '[$p]')
  explicit_port=34567
  readarray -t out < <(bash "$LAUNCH" --server_script "$SERVER_SCRIPT" --port "$explicit_port" --responses "$responses_json" --stdout_log "$BATS_TEST_TMPDIR/server.stdout" --stderr_log "$BATS_TEST_TMPDIR/server.stderr")
  PORT="${out[0]}"; PID="${out[1]}"
  assert_equal "$explicit_port" "$PORT"
  sleep 0.1
  curl --silent --fail http://127.0.0.1:"$PORT"/ > /dev/null || fail "curl failed on explicit port"
}

@test "missing responses argument errors" {
  enable_tracing
  if bash "$SERVER_SCRIPT" --port 22222 > "$BATS_TEST_TMPDIR/cr.out" 2> "$BATS_TEST_TMPDIR/cr.err"; then
    fail "Expected missing responses error"
  fi
  grep -qi "missing required argument --responses" "$BATS_TEST_TMPDIR/cr.err" || fail "Did not see missing responses message"
}

@test "nonexistent response file causes error" {
  bad=$(jq -n ' ["/no/such/file/123"] ')
  if bash "$SERVER_SCRIPT" --port 23456 --responses "$bad" > /dev/null 2> "$BATS_TEST_TMPDIR/err"; then
    fail "Expected error for missing file"
  fi
  grep -qi "Response file not found" "$BATS_TEST_TMPDIR/err" || fail "Missing file message not found"
}

@test "empty responses array: no listener" {
  empty='[]'
  _launch_canned "$empty"
  # Since no responses, server should exit quickly and no port stays open
  sleep 0.1
  if curl --silent --fail http://127.0.0.1:"$PORT"/ > /dev/null 2>&1; then
    fail "Server unexpectedly responded with empty responses array"
  fi
}

@test "invalid responses json value (malformed)" {
  # Provide malformed JSON string token
  if bash "$SERVER_SCRIPT" --port 22223 --responses '["missing]' > /dev/null 2> "$BATS_TEST_TMPDIR/err"; then
    fail "Expected malformed JSON error"
  fi
  grep -qi "value contains malformed JSON" "$BATS_TEST_TMPDIR/err" || fail "No JSON error message"
}

