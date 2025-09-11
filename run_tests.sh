#!/bin/bash

set -euo pipefail

# curlpilot/run_tests.sh

TEST_DIR="$(dirname "${BASH_SOURCE[0]}")/test"
PASSED_TESTS=0
FAILED_TESTS=0

echo "Running all tests in $TEST_DIR..."
echo "-----------------------------------"

# Find all test_*.sh files and run them
for test_file in $(find "$TEST_DIR" -type f -name "*_test.sh"); do
    echo -n "Running $test_file... " # -n to keep cursor on same line

    # Create a temporary file for output
    temp_output=$(mktemp)

    # Run the test, redirecting stdout and stderr to the temporary file
    if "$test_file" > "$temp_output" 2>&1; then
        echo "✅ PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "--- Output for $test_file (FAILED) ---"
        cat "$temp_output" # Display the captured output
        echo "---------------------------------------"
    fi

    rm "$temp_output" # Clean up the temporary file
    echo "-----------------------------------"
done

echo "Test Summary:"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ "$FAILED_TESTS" -gt 0 ]; then
    exit 1
fi