# test/mock/server/copilot_test.bats

setup() {
  bats_require_minimum_version 1.5.0

  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  log_debug "Sourced deps.bash"
  source "$BATS_TEST_DIRNAME/../../test_helper.bash"

  export MOCK_SERVER_SCRIPT="$PROJECT_ROOT/src/server/launch_server.bash"
  log_debug "Setup complete. MOCK_SERVER_SCRIPT is $MOCK_SERVER_SCRIPT"
}

_make_copilot_response() {
  local path="$1"
  local message_content="$2"

  local json_body
  json_body=$(jq -nc --arg msg "$message_content" \
    '{choices: [{message: {content: $msg}}]}')
  
  local len=${#json_body}
  cat > "$path" <<EOF
HTTP/1.1 200 OK
Content-Type: application/json
Connection: close
Content-Length: $len

$json_body
EOF
}

# Helper function to retry a command until it succeeds.
retry() {
  local attempts=$1
  local delay=$2
  local cmd="${@:3}"
  local i

  for i in $(seq 1 "$attempts"); do
    log_debug "Retry attempt #$i/$attempts for command: $cmd"
    run --separate-stderr $cmd
    if [[ "$status" -eq 0 ]]; then
      log_debug "Command succeeded."
      return 0
    fi
    log_debug "Command failed with status $status. Retrying in $delay seconds..."
    log_debug "output: $output"
    log_debug "stderr: $stderr"
    sleep "$delay"
  done

  log_debug "Command failed after $attempts attempts."
  return 1
}

@test "launch_copilot.bash starts a non-streaming server correctly" {
  log_debug "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"
  local message="Hello single JSON"
  log_debug "Message set to: '$message'"

  local response_file="$BATS_TEST_TMPDIR/response.http"
  _make_copilot_response "$response_file" "$message"
  local responses_json
  responses_json=$(jq -n --arg p "$response_file" '[$p]')

  log_debug "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stderr-log 3 \
    --stream=false --responses "$responses_json"
  log_debug "run command finished with status: $status"
  assert_success
  log_debug "assert_success finished"

  log_debug "Server launch command finished with status: $status"

  local port=${lines[0]}
  log_debug "port assigned: $port"
  local pid=${lines[1]}
  log_debug "pid assigned: $pid"
  log_debug "Server launched. Port: $port, PID: $pid"
  trap 'kill "$pid" &>/dev/null || true' EXIT
  log_debug "trap set"

  log_debug "Connecting client (curl)..."
  retry 4 0.5 curl --verbose --silent --show-error --max-time 2 "http://localhost:$port/"

  assert_success
  log_debug "Client command (curl) finished with status: $status"

  log_debug "Asserting final output..."
  log_debug "--- curl output ---"
  log_debug "$output"
  log_debug "--- end curl output ---"
  local actual_content
  actual_content=$(jq --raw-output '.choices[0].message.content' <<< "$output")
  assert_equal "$actual_content" "$message"
  log_debug "--- Test '$BATS_TEST_DESCRIPTION' finished ---"
}

@test "launch_copilot.bash starts a streaming server correctly" {
  log_debug "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"

  local message_content="Hello streaming world"
  log_debug "Message set to: '$message_content'"

  local response_file="$BATS_TEST_TMPDIR/response.http"
  _make_copilot_response "$response_file" "$message_content"
  local responses_json
  responses_json=$(jq -n --arg p "$response_file" '[$p]')

  log_debug "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log 3 \
    --stderr-log 3 \
    --responses "$responses_json"
  log_debug "run command finished with status: $status"
  assert_success
  log_debug "assert_success finished"

  log_debug "Server launch command finished with status: $status"

  local port=${lines[0]}
  log_debug "port assigned: $port"
  local pid=${lines[1]}
  log_debug "pid assigned: $pid"
  log_debug "Server launched. Port: $port, PID: $pid"
  trap 'kill "$pid" &>/dev/null || true' EXIT
  log_debug "trap set"

  log_debug "Connecting client (curl)..."
  retry 5 0.5 curl --silent --max-time 2 "http://localhost:$port/"

  assert_success
  log_debug "Client command (curl) finished with status: $status"

  log_debug "Asserting final output..."
  log_debug "--- curl output for streaming test ---"
  log_debug "$output"
  log_debug "--- end of curl output for streaming test ---"

  log_debug "Asserting final output..."
  local actual_content
  actual_content=$(jq --raw-output '.choices[0].message.content' <<< "$output")
  assert_equal "$actual_content" "$message_content"
  log_debug "--- Test '$BATS_TEST_DESCRIPTION' finished ---"
}
