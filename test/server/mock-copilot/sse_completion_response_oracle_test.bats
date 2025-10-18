# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.bats
set -euo pipefail

source test/test_helper.bash

_setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
}


@test "Generates an SSE stream that matches the expected output" {
  local expected_output_file
  expected_output_file="$PROJECT_ROOT/test/fixtures/copilot/sse-response.txt"

  [ -f "$expected_output_file" ] || fail "Golden file not found: $expected_output_file"

  local message_parts='["Hello", "!", " How", " can", " I", " assist", " you", " today", "?" ]'
  local prompt_tokens=7
  local created_ts=1757366620
  local id="chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"

  log_debug "expected output file $expected_output_file"

  cmd="
    source '$(dirname "$BATS_TEST_FILENAME")/.deps.bash'
    register_dep sse_generator 'server/mock-copilot/sse_completion_response.bash'
    exec_dep sse_generator \
    --message-parts '$message_parts' \
    --prompt-tokens '$prompt_tokens' \
    --created '$created_ts' \
    --id '$id'"

  log_debug "cmd: $cmd"

  run bash -c "$cmd"

  assert_success

  log_debug "ran sse generator"

  assert_equal "$output" "$(cat "$expected_output_file")"

  log_debug "--- Test '$BATS_TEST_DESCRIPTION' finished ---"

}
