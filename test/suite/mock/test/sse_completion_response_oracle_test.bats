# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.bats
set -euo pipefail

setup_file(){
  bats_require_minimum_version 1.5.0
}

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/../../../../deps.bash"
  log "Sourced deps.bash"

  source "$BATS_TEST_DIRNAME/../../test_helper.bash"

  log "Setup complete"
}


@test "Generates an SSE stream that matches the expected output" {
  local expected_output_file
  expected_output_file="$PROJECT_ROOT/test/suite/fixture/copilot/sse-response.txt"

  [ -f "$expected_output_file" ] || fail "Golden file not found: $expected_output_file"

  local message_parts='["Hello", "!", " How", " can", " I", " assist", " you", " today", "?"]'
  local prompt_tokens=7
  local created_ts=1757366620
  local id="chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"

  log "expected output file $expected_output_file"

  cmd="
    source \"$(dirname "$BATS_TEST_FILENAME")/../../../../deps.bash\"
    register_dep sse_generator \"test/suite/mock/server/copilot/sse_completion_response.bash\"
    exec_dep sse_generator \
    --message-parts '$message_parts' \
    --prompt-tokens \"$prompt_tokens\" \
    --created \"$created_ts\" \
    --id \"$id\""

  log "cmd: $cmd"

  echo "START_MALAISE" > /dev/null

  run bash -c "$cmd"

  assert_success

  log "ran sse generator"

  assert_equal "$output" "$(cat "$expected_output_file")"

  log "--- Test '$BATS_TEST_DESCRIPTION' finished ---"

  echo "END_MALAISE" > /dev/null
}
