#!/bin/bash

# ==============================================================================
# Test script for ajv/validate.js
#
# This script verifies the functionality of the JSON schema validation script
# by running it against several test cases:
#   1. Valid data against a schema.
#   2. Invalid data (wrong type) against a schema.
#   3. Invalid data (missing required property) against a schema.
#   4. Handling of non-existent files.
#   5. Handling of malformed JSON.
#   6. Correct usage message when no arguments are provided.
# ==============================================================================

# --- Setup ---
# Get the directory where the test script is located
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Path to the Node.js script to be tested
VALIDATE_SCRIPT_PATH="$TEST_DIR/../../ajv/validate.js"
# Create a temporary directory for test files
TEMP_DIR=$(mktemp -d)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Counters for test results
passed=0
failed=0

# --- Teardown ---
# Function to clean up the temporary directory on exit
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# --- Test Runner ---
# A function to run a test and check the output
# Arguments:
#   $1: Test name
#   $2: Expected output string (grep pattern)
#   $3: Command to run
run_test() {
  local test_name="$1"
  local expected_output="$2"
  shift 2
  local command_to_run=("$@")

  echo -n "🧪 Running test: '$test_name'... "

  # Execute command and capture output
  output=$("${command_to_run[@]}" 2>&1)

  # Check if output contains the expected string
  if echo "$output" | grep -q "$expected_output"; then
    echo -e "${GREEN}PASS${NC}"
    ((passed++))
  else
    echo -e "${RED}FAIL${NC}"
    echo "   - Expected to find: '$expected_output'"
    echo "   - Actual output was: '$output'"
    ((failed++))
  fi
}

# --- Test Cases ---

## 1. Test with valid data
cat > "$TEMP_DIR/schema1.json" <<EOL
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "number" }
  },
  "required": ["name", "age"]
}
EOL
cat > "$TEMP_DIR/data1_valid.json" <<EOL
{
  "name": "John Doe",
  "age": 30
}
EOL
run_test "Valid data" "✅ Data is valid!" node "$VALIDATE_SCRIPT_PATH" "$TEMP_DIR/schema1.json" "$TEMP_DIR/data1_valid.json"

## 2. Test with invalid data (wrong type)
cat > "$TEMP_DIR/data2_invalid.json" <<EOL
{
  "name": "Jane Doe",
  "age": "twenty-five"
}
EOL
run_test "Invalid data (wrong type)" "❌ Data is invalid:" node "$VALIDATE_SCRIPT_PATH" "$TEMP_DIR/schema1.json" "$TEMP_DIR/data2_invalid.json"

## 3. Test with invalid data (missing required property)
cat > "$TEMP_DIR/data3_missing.json" <<EOL
{
  "name": "Jane Doe"
}
EOL
run_test "Invalid data (missing property)" "❌ Data is invalid:" node "$VALIDATE_SCRIPT_PATH" "$TEMP_DIR/schema1.json" "$TEMP_DIR/data3_missing.json"

## 4. Test with non-existent files
run_test "Non-existent schema file" "An error occurred" node "$VALIDATE_SCRIPT_PATH" "$TEMP_DIR/nonexistent.json" "$TEMP_DIR/data1_valid.json"

## 5. Test with malformed JSON
cat > "$TEMP_DIR/malformed.json" <<EOL
{
  "name": "Bad JSON",
  "age": 40,
}
EOL
run_test "Malformed data file" "An error occurred" node "$VALIDATE_SCRIPT_PATH" "$TEMP_DIR/schema1.json" "$TEMP_DIR/malformed.json"


## 6. Test usage message with no arguments
run_test "Usage message" "Usage: node validate.js" node "$VALIDATE_SCRIPT_PATH"

# --- Summary ---
echo "---------------------------------"
echo "Test summary:"
echo -e "  ${GREEN}Passed: $passed${NC}"
echo -e "  ${RED}Failed: $failed${NC}"
echo "---------------------------------"

# Exit with a non-zero status code if any tests failed
if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
