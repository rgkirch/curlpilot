# test/mock_tests/server/copilot/completion_response_test.bash
set -euo pipefail

echo "🧪 Running tests for completion_response.bash..."
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep mock_completion "test/mocks/server/copilot/completion_response.bash"
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local expected_json="$2"
    shift 2 # The rest of the arguments ($@) are for the script.

    echo "--- Running Test: $test_name ---"

    local exit_code=0
    local raw_output
    raw_output=$(exec_dep mock_completion "$@" || exit_code=$?)

    if [ $exit_code -ne 0 ]; then
        echo "FAIL: $test_name - Script exited with error code $exit_code"
        echo "--- Output ---"; echo "$raw_output"; echo "--------------"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Iterate through each key (which is a jq filter) in the expected_json
    # and verify that the actual output matches the expected value.
    local filters_to_check
    filters_to_check=$(echo "$expected_json" | jq -r 'keys[]')
    for filter in $filters_to_check; do
        # Get the expected value as a compact JSON literal (e.g., "hello", 50, true).
        local expected_value
        expected_value=$(echo "$expected_json" | jq --compact-output --arg f "$filter" '.[$f]')

        # Get the actual value by running the filter against the raw output.
        local actual_value
        actual_value=$(echo "$raw_output" | jq --compact-output "$filter")

        if [[ "$expected_value" != "$actual_value" ]]; then
            echo "FAIL: $test_name"
            echo "  - Mismatch on filter: '$filter'"
            echo "  - Expected JSON value: $expected_value"
            echo "  -      Got JSON value: $actual_value"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1 # Stop checking on first failure
        fi
    done

    echo "PASS: $test_name"
    echo ""
}

# The expected results are now a map of { "jq filter": expected_value }.

run_test "Default values" \
    '{
      ".choices[0].message.content": "This is a mock Copilot response.",
      ".usage.prompt_tokens": 999
    }'
    # No arguments are passed, so the script's defaults are used.

run_test "Custom message" \
    '{
      ".choices[0].message.content": "Hello, world!",
      ".usage.completion_tokens": 3
    }' \
    --message-content "Hello, world!"

run_test "Override completion tokens" \
    '{
      ".choices[0].message.content": "test",
      ".usage.completion_tokens": 50
    }' \
    --message-content "test" --completion-tokens 50

run_test "Override prompt tokens" \
    '{
      ".usage.prompt_tokens": 123
    }' \
    --prompt-tokens 123

run_test "Override both tokens" \
    '{
      ".choices[0].message.content": "Full override",
      ".usage.completion_tokens": 77,
      ".usage.prompt_tokens": 88
    }' \
    --message-content "Full override" --completion-tokens 77 --prompt-tokens 88


echo "All tests completed."
if [ "$FAILED_TESTS" -gt 0 ]; then
    echo "$FAILED_TESTS tests failed."
    exit 1
fi
