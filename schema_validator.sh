#!/bin/bash
set -euo pipefail

# This script tests the functionality of schema_validator.sh.
# It must be run from the project's root directory.

echo "🧪 Running tests for schema_validator.sh..."

# --- Prerequisite Check ---
if ! command -v ajv &> /dev/null; then
  echo "❌ Prerequisite 'ajv-cli' not found. Please run: npm install -g ajv-cli" >&2
  exit 1
fi

# --- Test Setup ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

SCHEMA_FILE="$TEST_DIR/test.schema.json"
VALID_DATA='{"name": "Alice", "age": 30}'
INVALID_DATA='{"name": "Bob", "age": "thirty"}' # age should be a number

cat > "$SCHEMA_FILE" << EOF
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "number" }
  },
  "required": ["name", "age"]
}
EOF

# --- Test Runner ---
failures=0
run_test() {
  local description="$1"
  local command_to_run="$2"
  local expected_exit_code="$3"

  printf "  - %s... " "$description"

  set +e
  # Using eval to correctly process the command string with pipes and quotes
  output=$(eval "$command_to_run" 2>&1)
  local exit_code=$?
  set -e

  if [[ $exit_code -ne $expected_exit_code ]]; then
    printf "FAIL ❌\n"
    echo "    Expected exit code $expected_exit_code, but got $exit_code."
    echo "    Output:"
    echo "$output" | sed 's/^/    | /'
    failures=$((failures + 1))
  else
    printf "PASS ✅\n"
  fi
}

# --- Execute Tests ---
#
# CORRECTED: Use printf and ensure variables are expanded with double quotes.
# This correctly pipes the JSON content, not the variable name.
#
run_test "Success: Valid data should pass silently" \
  "printf '%s' \"$VALID_DATA\" | ./schema_validator.sh \"$SCHEMA_FILE\"" 0

run_test "Failure: Invalid data should fail with an error" \
  "printf '%s' \"$INVALID_DATA\" | ./schema_validator.sh \"$SCHEMA_FILE\"" 1

run_test "Failure: A non-existent schema file should cause an error" \
  "./schema_validator.sh '/no/such/file.json'" 1

run_test "Failure: Missing schema file argument should show usage" \
  "./schema_validator.sh" 1


# --- Final Report ---
if [[ $failures -gt 0 ]]; then
  echo "❌ $failures test(s) failed."
  exit 1
else
  echo "✅ All schema validator tests passed."
  exit 0
fi
