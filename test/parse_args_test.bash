#!/bin/bash

set -euo pipefail

# curlpilot/test/parse_args_test.bash

source "$(dirname "$0")/../deps.bash"
register "parse_args" "parse_args.bash"

# Test file for the unified, schema-driven argument_parser.bash

# Simple testing framework
PASS_COUNT=0
FAIL_COUNT=0
run_test() {
  local test_name="$1"
  local spec="$2"
  shift 2
  local -a args_array=("$@")

  # Pop the last three elements for expected values.
  local compare_json="${args_array[${#args_array[@]}-1]}"
  unset 'args_array[${#args_array[@]}-1]'
  local expected_exit_code="${args_array[${#args_array[@]}-1]}"
  unset 'args_array[${#args_array[@]}-1]'
  local expected="${args_array[${#args_array[@]}-1]}"
  unset 'args_array[${#args_array[@]}-1]'


  echo "--- Running Test: $test_name ---"

  local trace_log
  trace_log=$(mktemp)
  exec 3>"$trace_log"

  local script_to_test="${SCRIPT_REGISTRY[parse_args]}"

  local job_ticket

  job_ticket=$(jq -n \
    --argjson spec "$spec" \
    '{"spec": $spec, "args": $ARGS.positional}' \
    --args -- "${args_array[@]}" \
  )

  local output
  local exit_code
  # UPDATED: Pass job_ticket as a command-line argument instead of via stdin.
  if output=$(BASH_XTRACEFD=3 bash -x "$script_to_test" "$job_ticket" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  exec 3>&-

  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
    # In case of failure, reconstruct the full command for better error reporting
    local cmd_for_display
    printf -v cmd_for_display "%q " "${args_array[@]}"
    echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code."
    echo "Arguments were: $cmd_for_display"
    echo "--- Parser Script Output ---"
    echo "$output"
    echo "--- XTrace Log from $trace_log ---"
    cat "$trace_log"
    echo "---------------------------------"
    rm "$trace_log"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ "$expected_exit_code" -eq 0 ]]; then
    if [[ "$compare_json" == "true" ]]; then
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
        echo "--- XTrace Log from $trace_log ---"
        cat "$trace_log"
        echo "---------------------------------"
        rm "$trace_log"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
      fi
    else
      if ! echo "$output" | grep -qF "$expected"; then
        echo "FAIL: Plain text output does not contain expected string."
        echo "Expected to find: '$expected'"
        echo "Got output: '$output'"
        echo "--- XTrace Log from $trace_log ---"
        cat "$trace_log"
        echo "---------------------------------"
        rm "$trace_log"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
      fi
    fi
  else
    if ! echo "$output" | grep -qF "$expected"; then
      echo "FAIL: Expected error string not found."
      echo "Expected to find: '$expected'"
      echo "Got output:"
      echo "$output"
      echo "--- XTrace Log from $trace_log ---"
      cat "$trace_log"
      echo "---------------------------------"
      rm "$trace_log"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
    fi
  fi

  rm "$trace_log"
  echo "PASS: $test_name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# --- TEST CASES ---

MAIN_SPEC='{
  "model": {"type": "string", "default": "gpt-default"},
  "stream": {"type": "boolean", "default": true},
  "api_key": {"type": "string", "required": true},
  "retries": {"type": "number", "default": 3}
}'

# --- NOTE THE CHANGED SYNTAX FOR CALLING run_test ---
# --- Command-line arguments are now passed without surrounding quotes. ---

run_test "All args provided" \
  "$MAIN_SPEC" \
  --api-key=SECRET --model=gpt-4 --stream=false --retries=5 \
  '{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}' \
  0 true

run_test "Argument with space" \
  "$MAIN_SPEC" \
  --api-key SECRET --retries 0 \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0}' \
  0 true

run_test "Handles key=value parsing without order-of-operations bug" \
  '{"api_key": {"type": "string", "required": true}}' \
  --api-key=SECRET_VALUE \
  '{"api_key": "SECRET_VALUE"}' \
  0 true

run_test "Handles values containing an equals sign" \
  '{"connection_string": {"type": "string"}}' \
  --connection-string="user=admin;pass=123" \
  '{"connection_string": "user=admin;pass=123"}' \
  0 true

run_test "Standalone boolean flag" \
  "$MAIN_SPEC" \
  --api-key=SECRET --stream \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}' \
  0 true

run_test "Boolean set to false" \
  "$MAIN_SPEC" \
  --api-key=SECRET --stream=false \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3}' \
  0 true

run_test "Number type is respected" \
  "$MAIN_SPEC" \
  --api-key=SECRET --retries=10 \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10}' \
  0 true

run_test "String that looks like a number is still a string" \
  '{"version": {"type": "string"}}' \
  --version=1.0 \
  '{"version": "1.0"}' \
  0 true

run_test "Defaults are applied correctly" \
  "$MAIN_SPEC" \
  --api-key=SECRET \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}' \
  0 true

run_test "Default value can be the string 'null'" \
  '{"nullable_arg": {"type": "string", "default": "null"}}' \
  '{"nullable_arg": "null"}' \
  0 true

run_test "Default does not override passed value" \
  '{"config": {"type": "json", "default": {"theme": "dark", "user": "guest"}}}' \
  --config='{"user":"admin"}' \
  '{"config": {"user":"admin"}}' \
  0 true

run_test "Required argument failure" \
  "$MAIN_SPEC" \
  --model=gpt-4 \
  "Error: Required argument '--api-key' is missing." \
  1 true

run_test "Correctly handles value that looks like a flag" \
  '{"command": {"type": "string"}, "version": {"type": "boolean"}}' \
  --command '--version' \
  '{"command": "--version"}' \
  0 true

run_test "Unknown argument failure" \
  "$MAIN_SPEC" \
  --api-key=SECRET --non-existent-arg \
  "Error: Unknown option '--non-existent-arg'." \
  1 true

run_test "Value-taking arg requires a value" \
  "$MAIN_SPEC" \
  --api-key SECRET --model \
  "Error: Argument '--model' requires a value." \
  1 true

run_test "Help generation" \
  "$MAIN_SPEC" \
  --help \
  "  --help	Show this help message and exit." \
  0 false

# --- Special Case Tests ---
# A simplified test runner for cases that don't fit the standard model,
# like providing a job ticket that doesn't have a 'spec' or 'args' key.
run_special_test() {
  local test_name="$1"
  local job_ticket="$2"
  local expected_output="$3"
  local expected_exit_code="$4"

  echo "--- Running Test: $test_name ---"
  local script_to_test="${SCRIPT_REGISTRY[parse_args]}"
  local output
  local exit_code=0

  # Create a temp file to discard the xtrace logs.
  local trace_log
  trace_log=$(mktemp)

  # Redirect File Descriptor 3 to the temp file.
  exec 3>"$trace_log"

  # Run the script, sending xtrace output to FD 3 (via BASH_XTRACEFD).
  # The script's normal stdout and stderr are captured in the 'output' variable.
  if ! output=$(BASH_XTRACEFD=3 "$script_to_test" "$job_ticket" 2>&1); then
      exit_code=$?
  fi

  # Close FD 3 and clean up the now-unneeded log file.
  exec 3>&-
  rm "$trace_log"

  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
      echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code."
      echo "--- Script Output ---"
      echo "$output"
      echo "-----------------------"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return
  fi

  local expected_sorted
  local output_sorted
  expected_sorted=$(echo "$expected_output" | jq -S .)
  output_sorted=$(echo "$output" | jq -S .)

  if [[ "$output_sorted" != "$expected_sorted" ]]; then
      echo "FAIL: JSON output does not match expected."
      echo "Expected:"
      echo "$expected_sorted"
      echo "Got:"
      echo "$output_sorted"
      FAIL_COUNT=$((FAIL_COUNT + 1))
  else
      echo "PASS: $test_name"
      PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

run_special_test \
  "Handles empty JSON object '{}' as input" \
  '{}' \
  '{}' \
  0

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
