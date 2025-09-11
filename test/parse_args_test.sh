#!/bin/bash
# To enable debug tracing for tests, uncomment the line below
set -euo pipefail

# Test file for the unified, schema-driven argument_parser.sh

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
  local compare_json="${6:-true}"

  echo "--- Running Test: $test_name ---"

  local trace_log
  trace_log=$(mktemp)
  exec 3>"$trace_log"

  local cmd="set -x; $SCRIPT_TO_TEST '$spec' $args"

  local output
  local exit_code
  if output=$(BASH_XTRACEFD=3 bash -c "$cmd" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  exec 3>&-

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

run_test "All args provided" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --model=gpt-4 --stream=false --retries=5" \
  '{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}'

run_test "Argument with space" \
  "$MAIN_SPEC" \
  "--api-key SECRET --retries 0" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0}'

run_test "Handles key=value parsing without order-of-operations bug" \
  '{"api_key": {"type": "string", "required": true}}' \
  "--api-key=SECRET_VALUE" \
  '{"api_key": "SECRET_VALUE"}'

run_test "Handles values containing an equals sign" \
  '{"connection_string": {"type": "string"}}' \
  '--connection-string="user=admin;pass=123"' \
  '{"connection_string": "user=admin;pass=123"}'

run_test "Standalone boolean flag" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --stream" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}'

run_test "Boolean set to false" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --stream=false" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3}'

run_test "Number type is respected" \
  "$MAIN_SPEC" \
  "--api-key=SECRET --retries=10" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10}'

run_test "String that looks like a number is still a string" \
  '{"version": {"type": "string"}}' \
  "--version=1.0" \
  '{"version": "1.0"}'

run_test "Defaults are applied correctly" \
  "$MAIN_SPEC" \
  "--api-key=SECRET" \
  '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}'

run_test "Default value can be the string 'null'" \
  '{"nullable_arg": {"type": "string", "default": "null"}}' \
  "" \
  '{"nullable_arg": "null"}'

run_test "Default does not override passed value" \
  '{"config": {"type": "json", "default": {"theme": "dark", "user": "guest"}}}' \
  '--config="{\"user\":\"admin\"}"' \
  '{"config": {"user":"admin"}}'

run_test "Required argument failure" \
  "$MAIN_SPEC" \
  "--model=gpt-4" \
  "Error: Required argument '--api-key' is missing." \
  1

run_test "Correctly handles value that looks like a flag" \
  '{"command": {"type": "string"}, "version": {"type": "boolean"}}' \
  "--command '--version'" \
  '{"command": "--version"}'

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

run_test "Help generation" \
  "$MAIN_SPEC" \
  "--help" \
  "  --help	Show this help message and exit." \
  0 false

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
