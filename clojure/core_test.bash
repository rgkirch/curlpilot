#!/bin/bash
set -uo pipefail

# curlpilot/clojure/core_test.sh

# A simple, framework-free test script for hash_map.sh.
# It sources the functions and runs a series of checks.

# --- Test Runner Setup ---
# Load the functions to be tested
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# Counters for test results
PASSED_COUNT=0
FAILED_COUNT=0
TEST_COUNT=0

# Simple color definitions for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test function: Asserts that a command's output matches an expected value.
# Usage: assert_equals "description" "command_to_run" "expected_output"
assert_equals() {
    ((TEST_COUNT++))
    local description="$1"
    local command="$2"
    local expected="$3"
    local actual

    # Safely execute the command and capture its output
    actual=$(eval "$command" 2>/dev/null)

    if [ "$actual" == "$expected" ]; then
        ((PASSED_COUNT++))
        echo -e "${GREEN}✔ PASS:${NC} $description"
    else
        ((FAILED_COUNT++))
        echo -e "${RED}✖ FAIL:${NC} $description"
        echo -e "  - Expected: $expected"
        echo -e "  - Got:      $actual"
    fi
}

# Test function: Asserts that a command fails (exits with a non-zero status).
# Usage: assert_fail "description" "command_to_run"
assert_fail() {
    ((TEST_COUNT++))
    local description="$1"
    local command="$2"

    # Execute the command, suppressing output and checking exit code
    (eval "$command" &>/dev/null)
    local status=$?

    if [ "$status" -ne 0 ]; then
        ((PASSED_COUNT++))
        echo -e "${GREEN}✔ PASS:${NC} $description"
    else
        ((FAILED_COUNT++))
        echo -e "${RED}✖ FAIL:${NC} $description (Command succeeded but should have failed)"
    fi
}


# --- Test Cases ---

echo "--- Testing hash_map ---"
assert_equals "should create a valid JSON object" \
    'hash_map "key1" "value1" "key2" "42"' \
    '{"key1":"value1","key2":42}'

assert_equals "should handle boolean strings correctly" \
    'hash_map "active" "true" "inactive" "false"' \
    '{"active":true,"inactive":false}'

assert_fail "should fail with an odd number of arguments" \
    'hash_map "key1" "value1" "key2"'


echo -e "\n--- Testing get & get_in ---"
BASE_MAP='{"name":"John Doe","age":30,"city":"New York"}'
NESTED_MAP='{"user":{"details":{"name":"Jane","age":28}}}'

assert_equals "get: should retrieve a value" \
    'get "$BASE_MAP" "name"' \
    "John Doe"

assert_equals "get: should return 'null' for a non-existent key" \
    'get "$BASE_MAP" "nonexistent"' \
    "null"

assert_equals "get_in: should retrieve a nested value" \
    'get_in "$NESTED_MAP" "user" "details" "name"' \
    "Jane"

assert_equals "get_in: should return 'null' for a non-existent path" \
    'get_in "$NESTED_MAP" "user" "location"' \
    "null"


echo -e "\n--- Testing assoc & assoc_in ---"
assert_equals "assoc: should add a new key-value pair" \
    'assoc "$BASE_MAP" "occupation" "\\"Developer\\""' \
    '{"name":"John Doe","age":30,"city":"New York","occupation":"Developer"}'

assert_equals "assoc: should update an existing key" \
    'assoc "$BASE_MAP" "age" 31' \
    '{"name":"John Doe","age":31,"city":"New York"}'

assert_equals "assoc_in: should add a nested key-value pair" \
    'assoc_in "$NESTED_MAP" "user" "details" "city" "\\"London\\""' \
    '{"user":{"details":{"name":"Jane","age":28,"city":"London"}}}'

assert_equals "assoc_in: should update a nested value" \
    'assoc_in "$NESTED_MAP" "user" "details" "age" 29' \
    '{"user":{"details":{"name":"Jane","age":29}}}'


echo -e "\n--- Testing dissoc & dissoc_in ---"
assert_equals "dissoc: should remove a key" \
    'dissoc "$BASE_MAP" "city"' \
    '{"name":"John Doe","age":30}'

assert_equals "dissoc: should be idempotent for non-existent key" \
    'dissoc "$BASE_MAP" "nonexistent"' \
    "$BASE_MAP"

assert_equals "dissoc_in: should remove a nested key" \
    'dissoc_in "$NESTED_MAP" "user" "details" "age"' \
    '{"user":{"details":{"name":"Jane"}}}'

assert_equals "dissoc_in: should be idempotent for non-existent nested key" \
    'dissoc_in "$NESTED_MAP" "user" "details" "nonexistent"' \
    "$NESTED_MAP"

# --- Test Summary ---
echo -e "\n--- Summary ---"
echo "Total tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASSED_COUNT${NC}"
echo -e "${RED}Failed: $FAILED_COUNT${NC}"

# Exit with a non-zero status code if any tests failed
if [ "$FAILED_COUNT" -ne 0 ]; then
    exit 1
fi
