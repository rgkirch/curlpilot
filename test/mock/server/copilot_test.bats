# test/mock/server/copilot_test.bats
#set -euo pipefail

bats_require_minimum_version 1.5.0

source "$(dirname "$BATS_TEST_FILENAME")/../../../deps.bash"

load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# Path to the script we are testing.
MOCK_SERVER_SCRIPT="$PROJECT_ROOT/test/mock/server/launch_copilot.bash"

# ===============================================
# ==           TEST CASES                      ==
# ===============================================

@test "Starts in non-streaming mode and serves a single JSON object" {
  # Arrange: Define the raw message.
  local message="Hello single JSON"

  # Act: Start the server in non-streaming mode.
  run --separate-stderr bash "$MOCK_SERVER_SCRIPT" \
    --stdout-log out.log \
    --stderr-log err.log \
    --child-args -- \
    --stream=false \
    --message-content "$message"

  assert_success

  local port=${lines[0]}
  local pid=${lines[1]}
  trap 'kill "$pid" &>/dev/null || true' RETURN

  run curl --silent \
    --retry 10 \
    --retry-connrefused \
    --retry-delay 2 \
    "http://localhost:$port"

  # Assert: Verify the response is a valid JSON object with the correct content.
  assert_success
  assert_output --partial "\"content\":\"$message\""
}

# @test "Starts in streaming mode and chunks message content" {
#   # Arrange: Define the raw message.
#   local message="Hello streamed world"
#
#   # Act: Start the server. Note the '&' is removed. The server script
#   # backgrounds itself, so 'run' will capture the port/PID and exit correctly.
#   run --separate-stderr bash "$MOCK_SERVER_SCRIPT"  \
#     --stdout-log test.log \
#     --stderr-log test.log \
#     --child-args -- \
#     --message-content "$message"
#
#   assert_success
#
#   # Arrange: Capture port/PID and set a trap for cleanup.
#   local port=${lines[0]}
#   local pid=${lines[1]}
#   trap 'kill "$pid" &>/dev/null || true' RETURN
#
#
#   run curl --silent \
#     --retry 10 \
#     --retry-connrefused \
#     --retry-delay \
#     "http://localhost:$port"
#
#   # Act: Use the real `chat.bash` script to connect to our mock server.
#   run --separate-stderr bash "$PROJECT_ROOT/copilot/chat.bash" \
#     --api-endpoint "http://localhost:$port/" \
#     --messages '[{"role":"user","content":"test"}]'
#
#   # Assert: Verify the final, concatenated output is correct.
#   assert_success
#   assert_output "$message"
# }
#
#
# @test "Uses default message content when flag is not provided" {
#   # Arrange: The default message from the script's argument spec.
#   local expected_output="Hello from the mock server!"
#
#   # Act: Run the server with no arguments to test the default behavior.
#   run --separate-stderr bash "$MOCK_SERVER_SCRIPT"
#   assert_success
#
#   # Arrange: Capture port/PID and set a trap for cleanup.
#   local port=${lines[0]}
#   local pid=${lines[1]}
#   trap 'kill "$pid" &>/dev/null || true' RETURN
#
#   # Act: Connect and parse the default (streaming) response.
#   run --separate-stderr bash "$PROJECT_ROOT/copilot/chat.bash" \
#     --stdout-log test.log \
#     --stderr-log test.log \
#     --child-args -- \
#     --api-endpoint "http://localhost:$port/" \
#     --messages '[{"role":"user","content":"test"}]'
#
#   # Assert: Verify the final output matches the default message.
#   assert_success
#   assert_output "$expected_output"
# }
#
