# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.bats
set -euo pipefail

bats_require_minimum_version 1.5.0

export PROJECT_ROOT
PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# --- Test Runner Helper ---
# This function sets up the necessary environment inside the `run` subshell.
run_with_setup() {
  # Load the dependency management functions.
  source "$PROJECT_ROOT/deps.bash"

  # Register the specific dependency needed for this test suite.
  register_dep sse_generator "$PROJECT_ROOT/test/mocks/server/copilot/sse_completion_response.bash"

  # Execute the command that was passed as arguments to this function.
  "$@"
}

setup() {
  # Make the helper function available to the `run` command's subshell.
  export -f run_with_setup
}

# ===============================================
# ==           TEST CASE                       ==
# ===============================================

@test "Generates an SSE stream that matches the expected output" {
  # --- ARRANGE ---
  # Define test data and paths.
  local expected_output_file
  expected_output_file="$PROJECT_ROOT/test/mocks/sse-response.txt"

  # Use `fail` from bats-support for a clean pre-flight check.
  [ -f "$expected_output_file" ] || fail "Golden file not found: $expected_output_file"

  local message_parts='["Hello", "!", " How", " can", " I", " assist", " you", " today", "?"]'
  local prompt_tokens=7
  local created_ts=1757366620
  local id="chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"

  # --- ACT ---
  # Execute the script under test and capture its output.
  run --separate-stderr run_with_setup exec_dep sse_generator \
    --message-parts "$message_parts" \
    --prompt-tokens "$prompt_tokens" \
    --created "$created_ts" \
    --id "$id"

  # --- ASSERT ---
  # 1. Verify that the script ran without errors.
  assert_success

  # 2. Verify the captured output is identical to the golden file's content.
  # `assert_equal` will automatically show a colorized diff if they don't match.
  assert_equal "$output" "$(cat "$expected_output_file")"
}
