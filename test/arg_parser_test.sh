#!/bin/bash
set -euo pipefail

# Test file for the new parse_args.sh

# --- SETUP ---
TEST_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$TEST_DIR")
SCRIPT_TO_TEST="$PROJECT_ROOT/parse_args.sh"

# Simple testing framework
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local test_name="$1"
  local args="$2"
  local expected="$3"
  local expected_exit_code="${4:-0}"

  echo "--- Running Test: $test_name ---"

  # The command to run
  local cmd="$SCRIPT_TO_TEST $args"

  # Run the command in a subshell to capture output and exit code
  # without being affected by 'set -e'
  local output
  local exit_code
  if output=$(bash -c "$cmd" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  # Check exit code
  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
    echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code."
    echo "Command was: $cmd"
    echo "--- Parser Script Output ---"
    echo "$output"
    echo "--------------------------"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check output
  if [[ "$expected_exit_code" -eq 0 ]]; then
    # For success, compare JSON output
    local expected_sorted
    local output_sorted
    expected_sorted=$(echo "$expected" | jq -S .)
    output_sorted=$(echo "$output" | jq -S .)

    if [[ "$output_sorted" != "$expected_sorted" ]]; then
      echo "FAIL: JSON output does not match expected."
      echo "Command was: $cmd"
      echo "Expected (sorted):"
      echo "$expected_sorted"
      echo "Got (sorted):"
      echo "$output_sorted"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi
  else
    # For failure, check for the expected error string
    if ! echo "$output" | grep -qF "$expected"; then
      echo "FAIL: Expected error string not found."
      echo "Command was: $cmd"
      echo "Expected to find: '$expected'"
      echo "Got output:"
      echo "$output"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi
  fi

  echo "PASS: $test_name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# --- TEST CASES ---

# Test 1: Basic --key=value format
run_test "Basic --key=value" \
  "--model=gpt-4" \
  '{"model": "gpt-4"}'

# Test 2: Basic --key value format
run_test "Basic --key value" \
  "--model gpt-4" \
  '{"model": "gpt-4"}'

# Test 3: Simple boolean flag (becomes true)
run_test "Simple boolean flag" \
  "--stream" \
  '{"stream": true}'

# Test 4: Negated boolean flag (becomes false)
run_test "Negated --no- boolean flag" \
  "--no-stream" \
  '{"stream": false}'

# Test 5: Kebab-case key conversion to snake_case
run_test "Kebab-case to snake_case conversion" \
  "--api-endpoint=some_url" \
  '{"api_endpoint": "some_url"}'

# Test 6: Mixed argument types
run_test "Mixed argument types" \
  "--model=claude --stream --file-path /tmp/data.txt --no-debug" \
  '{"model": "claude", "stream": true, "file_path": "/tmp/data.txt", "debug": false}'

# Test 7: No arguments
run_test "No arguments" \
  "" \
  '{}'

# Test 8: Failure on invalid argument (not starting with --)
run_test "Failure on invalid argument format" \
  "positional" \
  "Error: Invalid argument format: 'positional'" \
  1

# Test 9: Value that looks like a flag
run_test "Value that looks like a flag" \
  "--command '--help'" \
  '{"command": "--help"}'

# Test 10: Multiple boolean flags
run_test "Multiple boolean flags" \
  "--verbose --force --no-cache" \
  '{"verbose": true, "force": true, "cache": false}'

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
