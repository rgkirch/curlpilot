# test/mock/server/copilot_test.bats
set -euo pipefail
#set -x
#export PS4='+(${BASH_SOURCE}:${LINENO}) '

bats_require_minimum_version 1.5.0

# Load helpers using the project root for robust paths.
source "$(dirname "$BATS_TEST_FILENAME")/../../../deps.bash"
load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# Path to the script we are testing.
MOCK_SERVER_SCRIPT="$PROJECT_ROOT/test/mock/server/copilot.bash"

# ===============================================
# ==           TEST CASES                      ==
# ===============================================

# bats test_tags=bats:focus
@test "Starts in streaming mode and chunks message content" {
  # Arrange: Define the full message we expect after parsing the stream.
  echo "i can't see this though" >&2
  local message_content="\"Hello streamed world\""

  # Act: Start the server in its default streaming mode.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" --message-content "$message_content"
  echo "output $output" >&2
  echo "stderr $stderr" >&2
  assert_success

  # Arrange: Capture port/PID and set a trap for cleanup.
  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act: Use the real `chat.bash` script to connect to our mock server and
  # parse the streamed response. This is the best way to verify the stream
  # is being generated correctly.
  run --separate-stderr bash "$PROJECT_ROOT/copilot/chat.bash" \
    --api-endpoint "http://localhost:$port/" \
    --messages '[{"role":"user","content":"test"}]'

  # Assert: Verify the final, concatenated output is correct.
  assert_success
  assert_output "$message_content"
}

@test "Starts in non-streaming mode and serves a single JSON object" {
  local message_content="\"Hello single JSON\""

  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" --stream=false --message-content "$message_content"
  assert_success

  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act: Connect with curl and pipe the output to jq for validation.
  run --separate-stderr curl --silent --max-time 1 "http://localhost:$port"

  # Assert: Verify the response is a valid JSON object with the correct content.
  assert_success
  assert_output --partial '"content":"Hello single JSON"'
}

@test "Handles multiple requests when message-content is a JSON array" {
  # Arrange: Define the sequence of responses.
  local messages_json='["First response", "Second response"]'

  # Act: Start the server, telling it to serve two separate responses.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" --stream=false --message-content "$messages_json"
  assert_success

  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act & Assert (First Request): Connect once and check the first response.
  run --separate-stderr curl --silent --max-time 1 "http://localhost:$port"
  assert_success
  assert_output --partial '"content":"First response"'

  # Act & Assert (Second Request): Connect again and check the second response.
  run --separate-stderr curl --silent --max-time 1 "http://localhost:$port"
  assert_success
  assert_output --partial '"content":"Second response"'
}

@test "Uses default message content when flag is not provided" {
  # Arrange: The default message from your new spec.
  local expected_output="Hello from the mock copilot server!"

  # Act: Run the server with NO arguments. It should now succeed.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT"
  assert_success

  # Arrange: Capture port/PID and set a trap for cleanup.
  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act: Use the real chat.bash to connect and parse the default (streaming) response.
  run --separate-stderr bash "$PROJECT_ROOT/copilot/chat.bash" \
    --api-endpoint "http://localhost:$port/" \
    --messages '[{"role":"user","content":"test"}]'

  # Assert: Verify the final output matches the default message.
  assert_success
  assert_output "$expected_output"
}
