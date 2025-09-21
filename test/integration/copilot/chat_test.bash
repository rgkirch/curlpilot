#!/usr/bin/env bats

# Load helpers using the project root for robust paths.
source "$(dirname "$BATS_TEST_FILENAME")/../../deps.bash"
load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

@test "Handles a multi-part streaming SSE response from a mock server" {
  # ARRANGE: Define the chunks of the streamed message and the expected final output.
  local message_parts='["Why don'\''t ","scientists ","trust atoms? ","Because they ","make up everything!"]'
  local expected_output="Why don't scientists trust atoms? Because they make up everything!"

  # ARRANGE: Define paths to the server helper and the response generator.
  local mock_server_script="$PROJECT_ROOT/test/mocks/server/copilot.bash"
  local sse_generator="$PROJECT_ROOT/test/mocks/server/copilot/sse_completion_response.bash"

  # ARRANGE: Start the mock server and capture its port and PID.
  local server_info
  server_info=$(bash "$mock_server_script" "$sse_generator" --message-parts "$message_parts")
  local port; port=$(echo "$server_info" | head -n 1)
  local nc_pid; nc_pid=$(echo "$server_info" | tail -n 1)

  # ARRANGE: Ensure the server is killed when the test is done.
  trap 'kill "$nc_pid" 2>/dev/null || true' RETURN
  sleep 0.1 # Give the server a moment to start listening.

  # ACT: Run the main chat script, pointing it at our mock server.
  # Use mock config and auth to ensure the test is isolated and repeatable.
  export CPO_CONFIG_BASH="$PROJECT_ROOT/test/mocks/config.bash"
  export CPO_COPILOT__AUTH_BASH="$PROJECT_ROOT/test/mocks/scripts/success/auth.bash"

  run bash "$PROJECT_ROOT/copilot/chat.bash" \
    --api-endpoint "http://localhost:$port/" \
    --messages '[{"role":"user","content":"Tell me a joke"}]'

  # ASSERT: Verify the script succeeded and that the final, parsed output is correct.
  assert_success
  assert_output "$expected_output"
}
