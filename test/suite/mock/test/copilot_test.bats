# test/mock/server/copilot_test.bats
# set -euo pipefail # Temporarily disabled to ensure all logs are written.



# ---

setup() {
  bats_require_minimum_version 1.5.0

  source "$(dirname "$BATS_TEST_FILENAME")/../../../../deps.bash"
  log "Sourced deps.bash"
  source "$BATS_TEST_DIRNAME/../../test_helper.bash"

  export MOCK_SERVER_SCRIPT="$PROJECT_ROOT/test/suite/mock/server/copilot/launch_server.bash"
  log "Setup complete. MOCK_SERVER_SCRIPT is $MOCK_SERVER_SCRIPT"
}

# Helper function to retry a command until it succeeds.
retry() {
  local attempts=$1
  local delay=$2
  local cmd="${@:3}"
  local i

  for i in $(seq 1 "$attempts"); do
    log "Retry attempt #$i/$attempts for command: $cmd"
    run --separate-stderr $cmd
    if [[ "$status" -eq 0 ]]; then
      log "Command succeeded."
      return 0
    fi
    log "Command failed with status $status. Retrying in $delay seconds..."
    log "output: $output"
    log "stderr: $stderr"
    sleep "$delay"
  done

  log "Command failed after $attempts attempts."
  return 1
}

@test "launch_copilot.bash starts a non-streaming server correctly" {
  log "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"
  local message="Hello single JSON"
  log "Message set to: '$message'"

  log "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stderr-log 3 \
    --child-args -- --stream=false --message-content "$message"
  log "run command finished with status: $status"
  assert_success
  log "assert_success finished"

  log "Server launch command finished with status: $status"

  local port=${lines[0]}
  log "port assigned: $port"
  local pid=${lines[1]}
  log "pid assigned: $pid"
  log "Server launched. Port: $port, PID: $pid"
  trap 'kill "$pid" &>/dev/null || true' EXIT
  log "trap set"

  log "Connecting client (curl)..."
  retry 4 0.5 curl --verbose --silent --show-error --max-time 2 "http://localhost:$port/"

  assert_success
  log "Client command (curl) finished with status: $status"

  log "Asserting final output..."
  log "--- curl output ---"
  log "$output"
  log "--- end curl output ---"
  local actual_content
  actual_content=$(jq --raw-output '.choices[0].message.content' <<< "$output")
  assert_equal "$actual_content" "$message"
  log "--- Test '$BATS_TEST_DESCRIPTION' finished ---"
}

@test "launch_copilot.bash starts a streaming server correctly" {
  log "--- Starting test: '$BATS_TEST_DESCRIPTION' ---"

  local message="Hello streaming world"
  log "Message set to: '$message'"

  log "Launching server..."
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log 3 \
    --stderr-log 3 \
    --child-args -- --message-content "$message"
  log "run command finished with status: $status"
  assert_success
  log "assert_success finished"

  log "Server launch command finished with status: $status"

  local port=${lines[0]}
  log "port assigned: $port"
  local pid=${lines[1]}
  log "pid assigned: $pid"
  log "Server launched. Port: $port, PID: $pid"
  trap 'kill "$pid" &>/dev/null || true' EXIT
  log "trap set"

  log "Connecting client (curl)..."
  retry 5 0.5 curl --silent --max-time 2 "http://localhost:$port/"

  assert_success
  log "Client command (curl) finished with status: $status"

  log "Asserting final output..."
  log "--- curl output for streaming test ---"
  log "$output"
  log "--- end of curl output for streaming test ---"

  log "Asserting final output..."
  assert_output --partial "\"Hello \""
  assert_output --partial "\"streaming \""
  assert_output --partial "\"world\""
  log "--- Test '$BATS_TEST_DESCRIPTION' finished ---"
}
