#!/bin/bash
set -euo pipefail

# Test file for the unified, schema-driven argument_parser.sh

# --- SETUP ---
TEST_DIR=$(dirname "$(readlink -f "$0")")
# Assuming the script to test is in a 'scripts' or similar subdirectory
# Adjust this path if your project structure is different.
PROJECT_ROOT=$(dirname "$TEST_DIR")
SCRIPT_TO_TEST="$PROJECT_ROOT/parse_args.sh"

# Simple testing framework
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local test_name="$1"
  local spec="$2"
  local args="$3"
  local expected="$4"
  local expected_exit_code="${5:-0}"
  local compare_json="${6:-true}"

  echo "--- Running Test: $test_name ---"

  # The command to run
  local cmd="$SCRIPT_TO_TEST '$spec' $args"

  # Run in a subshell to capture output and exit code without 'set -e' interference
  local output
  local exit_code
  if output=$(bash -c "$cmd" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  # 1. Check exit code
  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
    echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code."
    echo "Command was: $cmd"
    echo "--- Parser Script Output ---"
    echo "$output"
    echo "--------------------------"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # 2. Check output content
  if [[ "$expected_exit_code" -eq 0 ]]; then
    if [[ "$compare_json" == "true" ]]; then
      # For success, compare JSON
      local expected_sorted
      local output_sorted
      expected_sorted=$(echo "$expected" | jq -S .)
      output_sorted=$(echo "$output" | jq -S .)
      if [[ "$output_sorted" != "$expected_sorted" ]]; then
        echo "FAIL: JSON output does not match expected."
        echo "Expected:"
        echo "$expected_sorted"
        echo "Got:"
        echo "$output_sorted"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
      fi
    else
      # For success, check if output contains a plain text string
      if ! echo "$output" | grep -qF "$expected"; then
        echo "FAIL: Plain text output does not contain expected string."
        echo "Expected to find: '$expected'"
        echo "Got output: '$output'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
      fi
    fi
  else
    # For failure, check for the expected error string
    if ! echo "$output" | grep -qF "$expected"; then
      echo "FAIL: Expected error string not found."
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

# Schema for most tests
MAIN_SPEC='{
  "model": {"type": "string", "default": "gpt-default"},
  "stream": {"type": "boolean", "default": true},
  "api_key": {"type": "string", "required": true},
  "retries": {"type": "number", "default": 3}
}'

# --- Basic Success Cases ---
run_test "All args provided" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --model=gpt-4 --stream=false --retries=5" \
  '{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}'

run_test "Argument with space" \
  "$MAIN_SPEC" \
  "--api-key SECRET --retries 0" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0}'

# --- Boolean Handling ---
run_test "Standalone boolean flag" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --stream" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}' \
  0

run_test "Boolean set to false" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --stream=false" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3}'

# --- Type Handling (Numbers) ---
run_test "Number type is respected" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --retries=10" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10}' \
  0

run_test "String that looks like a number is still a string" \
  '{"version": {"type": "string"}}' \
  "--version=1.0" \
  '{"version": "1.0"}'

# --- Defaults and Required ---
run_test "Defaults are applied correctly" \
  "$MAIN_SPEC" \
  "--api-key=SECRET" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}'

run_test "Required argument failure" \
  "$MAIN_SPEC" \
  "--model=gpt-4" \
  "Error: Required argument '--api-key' is missing." \
  1

# --- Ambiguity Resolution ---
run_test "Correctly handles value that looks like a flag" \
  '{"command": {"type": "string"}, "help": {"type": "boolean"}}' \
  "--command '--help'" \
  '{"command": "--help"}'

# --- Edge Cases & Failures ---
run_test "Unknown argument failure" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --non-existent-arg" \
  "Error: Unknown option '--non-existent-arg'." \
  1

run_test "Value-taking arg requires a value" \
  "$MAIN_SPEC" \
  "--api-key SECRET --model" \
  "Error: Argument '--model' requires a value." \
  1

# --- Help Generation ---
run_test "Help generation" \
  '{"model": {"type": "string", "description": "The AI model to use."}}' \
  "--help" \
  "  --model	The AI model to use." \
  0 false

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
