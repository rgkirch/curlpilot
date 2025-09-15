#!/bin/bash

set -euo pipefail

# curlpilot/test/mock_tests/server/copilot/completion_response_test.bash

# Test script for mocks/server/copilot/completion_response.bash

SCRIPT_PATH="/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test/mocks/server/copilot/completion_response.bash"

FAILED_TESTS=0

# Function to run a test case
run_test() {
    local test_name="$1"
    local input_json="$2"
    local expected_message_content="$3"
    local expected_completion_tokens="$4"
    local expected_prompt_tokens="$5"

    echo "--- Running Test: $test_name ---"

    # Use 'read' and process substitution to correctly handle the null byte
    # This reads everything up to the first null byte into the 'main_json' variable
    IFS= read -r -d '' main_json < <(echo "$input_json" | "$SCRIPT_PATH")
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "FAIL: $test_name - Script exited with error code $exit_code"
        echo "Output: (Script output not captured due to null byte handling)"
        return 1
    fi

    actual_message_content=$(echo "$main_json" | jq -r '.choices[0].message.content')
    actual_completion_tokens=$(echo "$main_json" | jq -r '.usage.completion_tokens')
    actual_prompt_tokens=$(echo "$main_json" | jq -r '.usage.prompt_tokens')

    if [ "$actual_message_content" = "$expected_message_content" ] && \
       [ "$actual_completion_tokens" = "$expected_completion_tokens" ] && \
       [ "$actual_prompt_tokens" = "$expected_prompt_tokens" ]; then
        echo "PASS: $test_name"
    else
        echo "FAIL: $test_name"
        echo "  Expected Message Content: '$expected_message_content', Actual: '$actual_message_content'"
        echo "  Expected Completion Tokens: '$expected_completion_tokens', Actual: '$actual_completion_tokens'"
        echo "  Expected Prompt Tokens: '$expected_prompt_tokens', Actual: '$actual_prompt_tokens'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    echo ""
}

# Test Cases

# Test 1: Default values
run_test "Default Values" '{}' "This is a mock Copilot response." 8 999

# Test 2: Custom message content
run_test "Custom Message Content" '{"message_content": "Hello, world!"}' "Hello, world!" 3 999

# Test 3: Custom prompt_tokens
run_test "Custom Prompt Tokens" '{"prompt_tokens": 150}' "This is a mock Copilot response." 8 150

# Test 4: Custom completion_tokens
run_test "Custom Completion Tokens" '{"completion_tokens": 20}' "This is a mock Copilot response." 20 999

# Test 5: All custom values
run_test "All Custom Values" '{"message_content": "Test message for all values.", "completion_tokens": 10, "prompt_tokens": 50}' "Test message for all values." 10 50

# Test 6: Message content that results in fractional completion tokens
run_test "Fractional Completion Tokens" '{"message_content": "abc"}' "abc" 0 999

# Test 7: Empty message content
run_test "Empty Message Content" '{"message_content": ""}' "" 0 999

# Test 8: No input (should error, but run_test expects success for now)
# This test case needs a different approach as run_test expects a successful script execution.
# For now, we'll skip direct error testing within run_test.

echo "All tests completed."

if [ "$FAILED_TESTS" -gt 0 ]; then
    exit 1
fi
