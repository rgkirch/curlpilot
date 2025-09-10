#!/bin/bash

# Test file for parse_chat_args.sh

# Define paths
TEST_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$TEST_DIR") # curlpilot directory
COPILOT_DIR="$PROJECT_ROOT/copilot"
SCRIPT_TO_TEST="$COPILOT_DIR/parse_chat_args.sh"
MAIN_SCRIPT="$COPILOT_DIR/chat.sh" # Simulate the main script that sources it

# Function to run a test case
run_test() {
    local test_name="$1"
    args="$2" # Arguments to pass to parse_chat_args.sh
    declare -A expected_values # Expected values as an associative array
    eval "expected_values=($3)"
    local expected_exit_code="${4:-0}" # Default to 0 if not provided

    echo "--- Running Test: $test_name ---"

    # Execute the script and capture JSON output
    output=$(bash -c "$SCRIPT_TO_TEST $args" 2>&1)
    exit_code=$?

    echo "Output:"
    echo "$output"
    echo "Exit Code: $exit_code"

    if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
        echo "FAIL: $test_name - Expected exit code $expected_exit_code, got $exit_code"
        return 1
    fi

    if [[ "$expected_exit_code" -ne 0 ]]; then
        # If an error is expected, we don't parse JSON, just check exit code and error message
        if echo "$output" | grep -q "Error: Invalid value for --stream"; then
            echo "PASS: $test_name"
            return 0
        else
            echo "FAIL: $test_name - Expected error message not found"
            return 1
        fi
    fi

    # Parse JSON output using jq and verify values
    for key in "${!expected_values[@]}"; do
        local expected_val="${expected_values[$key]}"
        local actual_val=$(echo "$output" | jq -r ".""$key""")

        if [[ "$actual_val" != "$expected_val" ]]; then
            echo "FAIL: $test_name - $key: Expected '$expected_val', got '$actual_val'"
            return 1
        fi
    done

    echo "PASS: $test_name"
    return 0
}

# Test Cases

# Test 1: No arguments (should use defaults)
run_test "Default arguments" \
    "" \
    "[MODEL]=gpt-4.1
[API_ENDPOINT]=https://api.githubcopilot.com/chat/completions
[STREAM_ENABLED]=true
[SCRIPT_DIR]=$COPILOT_DIR
[PROJECT_ROOT]=$PROJECT_ROOT
[CONFIG_DIR]=$HOME/.config/curlpilot
[TOKEN_FILE]=$HOME/.config/curlpilot/token.txt
[LOGIN_SCRIPT]=$PROJECT_ROOT/login.sh"

# Test 2: Custom model
run_test "Custom model" \
    "--model=gpt-3.5-turbo" \
    "[MODEL]=gpt-3.5-turbo
[API_ENDPOINT]=https://api.githubcopilot.com/chat/completions
[STREAM_ENABLED]=true
[SCRIPT_DIR]=$COPILOT_DIR
[PROJECT_ROOT]=$PROJECT_ROOT
[CONFIG_DIR]=$HOME/.config/curlpilot
[TOKEN_FILE]=$HOME/.config/curlpilot/token.txt
[LOGIN_SCRIPT]=$PROJECT_ROOT/login.sh"

# Test 3: Stream disabled
run_test "Stream disabled" \
    "--stream=false" \
    "[MODEL]=gpt-4.1
[API_ENDPOINT]=https://api.githubcopilot.com/chat/completions
[STREAM_ENABLED]=false
[SCRIPT_DIR]=$COPILOT_DIR
[PROJECT_ROOT]=$PROJECT_ROOT
[CONFIG_DIR]=$HOME/.config/curlpilot
[TOKEN_FILE]=$HOME/.config/curlpilot/token.txt
[LOGIN_SCRIPT]=$PROJECT_ROOT/login.sh"

# Test 4: Custom API endpoint
run_test "Custom API endpoint" \
    "--api-endpoint=https://example.com/api" \
    "[MODEL]=gpt-4.1
[API_ENDPOINT]=https://example.com/api
[STREAM_ENABLED]=true
[SCRIPT_DIR]=$COPILOT_DIR
[PROJECT_ROOT]=$PROJECT_ROOT
[CONFIG_DIR]=$HOME/.config/curlpilot
[TOKEN_FILE]=$HOME/.config/curlpilot/token.txt
[LOGIN_SCRIPT]=$PROJECT_ROOT/login.sh"

# Test 5: All custom arguments
run_test "All custom arguments" \
    "--model=test-model" \
    "--api-endpoint=http://localhost/test" \
    "--stream=false" \
    "[MODEL]=test-model
[API_ENDPOINT]=http://localhost/test
[STREAM_ENABLED]=false
[SCRIPT_DIR]=$COPILOT_DIR
[PROJECT_ROOT]=$PROJECT_ROOT
[CONFIG_DIR]=$HOME/.config/curlpilot
[TOKEN_FILE]=$HOME/.config/curlpilot/token.txt
[LOGIN_SCRIPT]=$PROJECT_ROOT/login.sh"

# Test 6: Invalid stream value (should exit with error)
run_test "Invalid stream value" \
    "--stream=invalid" \
    "" \
    1


