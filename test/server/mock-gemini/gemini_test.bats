#!/usr/bin/env bats
# test/mock/test/gemini_test.bats

# --

setup() {
  bats_require_minimum_version 1.5.0

  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  log_debug "Sourced deps.bash"
  source "$BATS_TEST_DIRNAME/../../test_helper.bash"

  export MOCK_SERVER_SCRIPT="$PROJECT_ROOT/src/server/launch_server.bash"
  log_debug "Setup complete. MOCK_SERVER_SCRIPT is $MOCK_SERVER_SCRIPT"
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



@test "launch_gemini.bash starts a streaming server correctly" {
  log_debug "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"

  local message="Hello streaming world"
  log_debug "Message set to: '$message'"

  log_debug "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log 3 \
    --stderr-log 3 \
    --message-content "$message"
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
  local actual_content=$(echo "$output" | jq -r '.response.candidates[0].content.parts[0].text')
  if [ "$actual_content" != "$message" ]; then
    echo "Assertion failed!"
    echo "Expected: $message"
    echo "Actual:   $actual_content"
    fail "The actual content did not match the expected content."
  fi
  log_debug "--- Test '$BATS_TEST_DESCRIPTION' finished ---"
}
