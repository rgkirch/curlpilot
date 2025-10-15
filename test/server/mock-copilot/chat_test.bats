# test/mock/server/chat_test.bats

source test/test_helper.bash

_setup_file(){
  export BATS_TEST_TIMEOUT=15
}

_setup() {
  source deps.bash
  export MOCK_SERVER_SCRIPT="$PROJECT_ROOT/src/server/launch_server.bash"
  mock_dep "client/copilot/auth.bash" "mock/stub/success/auth.bash"
  mock_dep "config.bash" "mock/stub/success/config.bash"
}

sse_generator() {
  source deps.bash
  _exec_dep "$PROJECT_ROOT/src/server/mock-copilot/sse_completion_response.bash" sse_completion_response "$@"
}

_make_response() {
  local path="$1" body="$2"
  local len=${#body}
  cat > "$path" <<EOF
HTTP/1.1 200 OK
Content-Type: text/event-stream
Connection: close
Content-Length: $len

$body
EOF
}

@test "chat.bash correctly processes a streaming response" {
  log_debug "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"

  # 1. Generate the mock SSE body using the dedicated script.
  local message_parts='["Hello ", "streaming ", "chat"]'
  local response_body
  response_body=$(sse_generator --message-parts "$message_parts")

  # 2. Create a full HTTP response file.
  local response_file="$BATS_TEST_TMPDIR/response.http"
  _make_response "$response_file" "$response_body"
  local responses_json
  responses_json=$(jq -n --arg p "$response_file" '[$p]')

  local request_log_dir="$BATS_TEST_TMPDIR/requests"
  mkdir -p "$request_log_dir"

  log_debug "Launching server..."
  # 3. Launch the canned server with the generated response file.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log 3 \
    --stderr-log 3 \
    --request-dir "$request_log_dir" \
    --responses "$responses_json"
  assert_success
  log_debug "Server launch command finished with status: $status"

  local port=${lines[0]}
  local pid=${lines[1]}
  log_debug "Server launched. Port: $port, PID: $pid"

  #trap 'kill "$pid" &>/dev/null || true' EXIT

  log_debug "Running chat.bash client..."
  # Export the API_ENDPOINT so the stubbed config.bash can access it.
  export API_ENDPOINT="http://localhost:$port/"

  # Run chat.bash. The API endpoint is now handled by the exported variable and the mocked config.
  run --separate-stderr bash "$PROJECT_ROOT/src/client/copilot/chat.bash" \
    --messages '[{"role": "user", "content": "Say hello"}]'

  log_debug "chat.bash finished with status: $status"
  log_debug "--- chat.bash output ---"
  log_debug "$output"
  log_debug "--- end chat.bash output ---"

  assert_success

  log_debug "Asserting request body was received by server..."
  local request_log_file="$request_log_dir/request.0.log"
  assert_file_contains "$request_log_file" "Say hello"
  log_debug "Request body assertion passed."

  log_debug "Asserting auth header was passed..."
  assert_file_contains "$request_log_file" "Authorization: Bearer mock_token"
  log_debug "Auth header assertion passed."

  log_debug "Asserting final output..."
  assert_output "Hello streaming chat"

  log_debug "--- Test '$BATS_TEST_DESCRIPTION' finished ---"

}
