# test/mock/server/copilot_test.bats
# set -euo pipefail # Temporarily disabled to ensure all logs are written.

setup_file(){
  export BATS_TEST_TIMEOUT=10
}

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  log "Sourced deps.bash"
  log "BATS_TEST_DIRNAME $BATS_TEST_DIRNAME"
  source "$BATS_TEST_DIRNAME/../../test_helper.bash"

  log "Loaded test helper"

  mock_dep "client/copilot/auth.bash" "mock/stub/success/auth.bash"
  mock_dep "config.bash" "mock/stub/success/config.bash"
  log "Dependencies mocked."

  export MOCK_SERVER_SCRIPT="$PROJECT_ROOT/src/server/mock-copilot/launch_server.bash"
  log "Setup complete. MOCK_SERVER_SCRIPT is $MOCK_SERVER_SCRIPT"
}

@test "chat.bash correctly processes a streaming response" {
  log "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"

  local message="Hello streaming chat"
  log "Message set to: '$message'"

  log "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log ${CURLPILOT_LOG_TARGET:-2} \
    --stderr-log ${CURLPILOT_LOG_TARGET:-2} \
    --child-args -- --message-content "$message"
  assert_success
  log "Server launch command finished with status: $status"

  local port=${lines[0]}
  local pid=${lines[1]}
  log "Server launched. Port: $port, PID: $pid"

  trap 'kill "$pid" &>/dev/null || true' EXIT

  log "Running chat.bash client..."
  # Export the API_ENDPOINT so the stubbed config.bash can access it.
  export API_ENDPOINT="http://localhost:$port/"

  # Run chat.bash. The API endpoint is now handled by the exported variable and the mocked config.
  run bash "$PROJECT_ROOT/src/client/copilot/chat.bash" \
    --messages '[{"role": "user", "content": "Say hello"}]'

  log "chat.bash finished with status: $status"
  log "--- chat.bash output ---"
  log "$output"
  log "--- end chat.bash output ---"

  assert_success

  log "Asserting request body was received by server..."
  request_log_file="$BATS_TEST_TMPDIR/request.log"
  assert_file_contains "$request_log_file" "Say hello"
  log "Request body assertion passed."

  log "Asserting auth header was passed..."
  assert_file_contains "$request_log_file" "Authorization: Bearer mock_token"
  log "Auth header assertion passed."

  log "Asserting final output..."
  assert_output "Hello streaming chat"

    log "--- Test '$BATS_TEST_DESCRIPTION' finished ---"

}
