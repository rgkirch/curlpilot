#!/bin/bash
set -euo pipefail

# Test file for the new schema-driven parse_args.sh

# --- SETUP ---
TEST_DIR=$(dirname "$(readlink -f "$0")")
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
  local compare_json="${6:-true}" # New parameter, defaults to true

  echo "--- Running Test: $test_name ---"

  # Create a temporary file for the trace log
  local trace_log
  trace_log=$(mktemp)

  # Open file descriptor 3 for writing to the trace log
  exec 3>"$trace_log"

  # The command to run
  local cmd="$SCRIPT_TO_TEST '$spec' $args"
  
  # Run the command with xtrace redirected to FD 3
  # Use a subshell to capture the exit code without triggering set -e
  local temp_output
  local temp_exit_code
  if temp_output=$(BASH_XTRACEFD=3 bash -c "$cmd" 2>&1); then
    temp_exit_code=0
  else
    temp_exit_code=$?
  fi
  output="$temp_output"
  exit_code="$temp_exit_code"

  # Close the file descriptor
  exec 3>&-

  # Check exit code
  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
    echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code."
    echo "Command was: $cmd"
    echo "--- Parser Script Output ---"
    echo "$output"
    echo "--- XTrace Log from $trace_log ---"
    cat "$trace_log"
    echo "---------------------------------"
    rm "$trace_log"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check output
  if [[ "$expected_exit_code" -eq 0 ]]; then
    if [[ "$compare_json" == "true" ]]; then
      # For success, compare JSON
      expected_sorted=$(echo "$expected" | jq -S .)
      output_sorted=$(echo "$output" | jq -S .)
      if [[ "$output_sorted" != "$expected_sorted" ]]; then
        echo "FAIL: JSON output does not match expected."
        echo "Expected:"
        echo "$expected_sorted"
        echo "Got:"
        echo "$output_sorted"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        rm "$trace_log" # Clean up even on this failure
        return
      fi
    else
      # For success, compare plain text
      if ! printf %b "$output" | grep -qP "$expected"; then
        echo "FAIL: Plain text output does not contain expected string."
        echo "Expected to find: '$expected'"
        echo "Got output: '$output'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        rm "$trace_log" # Clean up even on this failure
        return
      fi
    fi
  else
    # For failure, check for error string
    if ! echo "$output" | grep -qF "$expected"; then
      echo "FAIL: Expected error string not found."
      echo "Expected to find: '$expected'"
      echo "Got output:"
      echo "$output"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      rm "$trace_log" # Clean up even on this failure
      return
    fi
  fi

  # Clean up the log file on success
  rm "$trace_log"

  echo "PASS: $test_name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# --- TEST CASES ---

# Test 1: Basic success
SPEC_1='{"model": {"type": "string"}, "stream": {"type": "boolean"}}'
ARGS_1="--model=gpt4 --stream=false"
EXPECTED_1='{"model": "gpt4", "stream": false}'
run_test "Basic success" "$SPEC_1" "$ARGS_1" "$EXPECTED_1"

# Test 2: Default values
SPEC_2='{"model": {"type": "string", "default": "gpt-default"}, "stream": {"type": "boolean", "default": true}}'
ARGS_2=""
EXPECTED_2='{"model": "gpt-default", "stream": true}'
run_test "Default values" "$SPEC_2" "$ARGS_2" "$EXPECTED_2"

# Test 3: Override one default
ARGS_3="--stream=false"
EXPECTED_3='{"model": "gpt-default", "stream": false}'
run_test "Override one default" "$SPEC_2" "$ARGS_3" "$EXPECTED_3"

# Test 4: Required argument failure
SPEC_4='{"model": {"type": "string", "required": true}}'
ARGS_4=""
EXPECTED_4="Error: Required argument '--model' is missing."
run_test "Required argument failure" "$SPEC_4" "$ARGS_4" "$EXPECTED_4" 1

# Test 5: Unknown argument failure
SPEC_5='{"model": {"type": "string"}}'
ARGS_5="--stream=true"
EXPECTED_5="Error: Unknown option '--stream'."
run_test "Unknown argument failure" "$SPEC_5" "$ARGS_5" "$EXPECTED_5" 1

# Test 6: Help generation
SPEC_6='{"model": {"type": "string", "description": "The AI model."}}'
ARGS_6="--help"
EXPECTED_6="  --model\tThe AI model."
run_test "Help generation" "$SPEC_6" "$ARGS_6" "$EXPECTED_6" 0 false

# Test 7: Boolean flag formats
SPEC_7='{"feature_a": {"type": "boolean"}, "feature_b": {"type": "boolean"}}'
ARGS_7="--feature-a --no-feature-b"
EXPECTED_7='{"feature_a": true, "feature_b": false}'
run_test "Boolean flag formats" "$SPEC_7" "$ARGS_7" "$EXPECTED_7"

# Test 8: Argument with space
SPEC_8='{"model": {"type": "string"}}'
ARGS_8="--model gpt-xyz"
EXPECTED_8='{"model": "gpt-xyz"}'
run_test "Argument with space" "$SPEC_8" "$ARGS_8" "$EXPECTED_8"

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
