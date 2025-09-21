# test/mock/server/copilot_test.bats

# Load helpers using the project root for robust paths.
source "$(dirname "$BATS_TEST_FILENAME")/../../../../deps.bash"
load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# Path to the script we are testing.
MOCK_SERVER_SCRIPT="$PROJECT_ROOT/test/mock/server/copilot.bash"

# ===============================================
# ==           TEST CASES                      ==
# ===============================================

@test "Starts in streaming mode and chunks message content" {
  # Arrange: Define the full message we expect after parsing the stream.
  local message_content="Hello streamed world"

  # Act: Start the server in its default streaming mode.
  run bash "$MOCK_SERVER_SCRIPT" --message-content "$message_content"
  assert_success

  # Arrange: Capture port/PID and set a trap for cleanup.
  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act: Use the real `chat.bash` script to connect to our mock server and
  # parse the streamed response. This is the best way to verify the stream
  # is being generated correctly.
  run bash "$PROJECT_ROOT/copilot/chat.bash" \
    --api-endpoint "http://localhost:$port/" \
    --messages '[{"role":"user","content":"test"}]'

  # Assert: Verify the final, concatenated output is correct.
  assert_success
  assert_output "$message_content"
}

@test "Starts in non-streaming mode and serves a single JSON object" {
  local message_content="Hello single JSON"

  run bash "$MOCK_SERVER_SCRIPT" --stream=false --message-content "$message_content"
  assert_success

  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act: Connect with curl and pipe the output to jq for validation.
  run curl --silent --max-time 1 "http://localhost:$port"

  # Assert: Verify the response is a valid JSON object with the correct content.
  assert_success
  assert_output --partial '"content":"Hello single JSON"'
}

@test "Handles multiple requests when message-content is a JSON array" {
  # Arrange: Define the sequence of responses.
  local messages_json='["First response", "Second response"]'

  # Act: Start the server, telling it to serve two separate responses.
  run bash "$MOCK_SERVER_SCRIPT" --stream=false --message-content "$messages_json"
  assert_success

  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN
  sleep 0.1

  # Act & Assert (First Request): Connect once and check the first response.
  run curl --silent --max-time 1 "http://localhost:$port"
  assert_success
  assert_output --partial '"content":"First response"'

  # Act & Assert (Second Request): Connect again and check the second response.
  run curl --silent --max-time 1 "http://localhost:$port"
  assert_success
  assert_output --partial '"content":"Second response"'
}

@test "Fails if --message-content is not provided" {
  # The --separate-stderr flag is needed to check stderr.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT"

  assert_failure
  assert_stderr --partial "Missing required value for key: message_content"
}
