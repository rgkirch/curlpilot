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



