#!/bin/bash

set -euo pipefail

# curlpilot/test/chat_test_non_streaming.bash

# Get the directory of the test script
TEST_DIR=$(dirname "$(readlink -f "$0")")

# This is the non-streaming test for chat.bash

# Define the mock script path
MOCK_REQUEST_SCRIPT="$TEST_DIR/mock/server/copilot/completion_response.bash"

# Set the environment variable to override the dependency
export CPO_COPILOT__REQUEST_SH="$MOCK_REQUEST_SCRIPT"

# Define the absolute path to the chat.bash script
CHAT_SH_PATH="/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/copilot/chat.bash"

# Run the chat.bash script with stream=false
output=$(echo '{"role": "user", "content": "hi"}' | "$CHAT_SH_PATH" --stream=false)

# Assert the output
expected_output="This is a mock Copilot response."

if [[ "$output" == "$expected_output" ]]; then
  echo "Test passed!"
else
  echo "Test failed!"
  echo "Expected: $expected_output"
  echo "Got: $output"
  exit 1
fi
