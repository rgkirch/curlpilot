# curlpilot/test/parse_args_test.bash
set -euo pipefail
set -x

source "$(dirname "$0")/../deps.bash"
register_dep "parse_args" "parse_args.bash"

# Test file for the unified, schema-driven argument_parser.bash

# --- Test Framework ---
PASS_COUNT=0
FAIL_COUNT=0

# Private helper function to handle the core logic of running a test.
# It sets up, executes the script, captures output, and validates the exit code.
# It prints the script's stdout for the calling wrapper function to check.
_execute_test() {
  local test_name="$1"
  local spec="$2"
  local expected_exit_code="$3"
  shift 3
  local -a args_array=("$@")

  echo "--- Running Test: $test_name ---" >&2

  local script_to_test="${SCRIPT_REGISTRY[parse_args]}"
  local job_ticket
  job_ticket=$(jq -n \
    --argjson spec "$spec" \
    '{"spec": $spec, "args": $ARGS.positional}' \
    --args -- "${args_array[@]}" \
  )

  local output
  local exit_code
  # We disable errexit (-e) just for the script execution to capture its exit code
  set +e
  output=$(bash "$script_to_test" "$job_ticket" 2>&1)
  exit_code=$?
  set -e

  if [[ "$exit_code" -ne "$expected_exit_code" ]]; then
    echo "FAIL: Expected exit code $expected_exit_code, but got $exit_code for test '$test_name'."
    echo "--- Parser Script Output ---"
    echo "$output"
    echo "----------------------------"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1 # Signal failure to the calling function
  fi

  # Pass the output along for content validation
  echo "$output"
  return 0
}

# Public test runner for cases expecting JSON output.
run_json_test() {
  local test_name="$1"
  local spec="$2"
  local expected_json="$3"
  local expected_exit_code="$4"
  shift 4 # Move past the test runner args

  # The rest of the arguments are for the script under test
  local -a script_args=("$@")
  local output

  # Call the helper; if it fails (returns non-zero), we're done.
  if ! output=$(_execute_test "$test_name" "$spec" "$expected_exit_code" "${script_args[@]}"); then
    return
  fi

  local expected_sorted
  local output_sorted
  expected_sorted=$(echo "$expected_json" | jq -S .)
  output_sorted=$(echo "$output" | jq -S .)

  if [[ "$output_sorted" != "$expected_sorted" ]]; then
    echo "FAIL: JSON output does not match expected for test '$test_name'."
    echo "Expected:"
    echo "$expected_sorted"
    echo "Got:"
    echo "$output_sorted"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  echo "PASS: $test_name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Public test runner for cases expecting plain text (e.g., error messages).
run_text_test() {
  local test_name="$1"
  local spec="$2"
  local expected_text="$3"
  local expected_exit_code="$4"
  shift 4
  local -a script_args=("$@")
  local output

  if ! output=$(_execute_test "$test_name" "$spec" "$expected_exit_code" "${script_args[@]}"); then
    return
  fi

  if ! echo "$output" | grep -qF "$expected_text"; then
    echo "FAIL: Expected text not found for test '$test_name'."
    echo "Expected to find: '$expected_text'"
    echo "Got output: '$output'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  echo "PASS: $test_name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# --- TEST CASES ---

MAIN_SPEC='{
  "_description": "A test script with various argument types.",
  "model": {"type": "string", "default": "gpt-default", "description": "The model to use."},
  "stream": {"type": "boolean", "default": true, "description": "Enable streaming responses."},
  "api_key": {"type": "string", "required": true, "description": "The API key for authentication."},
  "retries": {"type": "number", "default": 3, "description": "Number of retries on failure."}
}'

run_json_test "All args provided" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}' 0 \
  --api-key=SECRET --model=gpt-4 --stream=false --retries=5

run_json_test "Argument with space" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0}' 0 \
  --api-key SECRET --retries 0

run_json_test "Handles key=value parsing without order-of-operations bug" \
  '{"api_key": {"type": "string", "required": true}}' '{"api_key": "SECRET_VALUE"}' 0 \
  --api-key=SECRET_VALUE

run_json_test "Handles values containing an equals sign" \
  '{"connection_string": {"type": "string"}}' '{"connection_string": "user=admin;pass=123"}' 0 \
  --connection-string="user=admin;pass=123"

run_json_test "Standalone boolean flag" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}' 0 \
  --api-key=SECRET --stream

run_json_test "Boolean set to false" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3}' 0 \
  --api-key=SECRET --stream=false

run_json_test "Number type is respected" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10}' 0 \
  --api-key=SECRET --retries=10

run_json_test "String that looks like a number is still a string" \
  '{"version": {"type": "string"}}' '{"version": "1.0"}' 0 \
  --version=1.0

run_json_test "Defaults are applied correctly" \
  "$MAIN_SPEC" '{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}' 0 \
  --api-key=SECRET

run_json_test "Default value can be the string 'null'" \
  '{"nullable_arg": {"type": "string", "default": "null"}}' '{"nullable_arg": "null"}' 0

run_json_test "Default does not override passed value" \
  '{"config": {"type": "json", "default": {"theme": "dark", "user": "guest"}}}' '{"config": {"user":"admin"}}' 0 \
  --config='{"user":"admin"}'

run_text_test "Required argument failure" \
  "$MAIN_SPEC" "Error: Required argument '--api-key' is missing." 1 \
  --model=gpt-4

run_json_test "Correctly handles value that looks like a flag" \
  '{"command": {"type": "string"}, "version": {"type": "boolean"}}' '{"command": "--version"}' 0 \
  --command '--version'

run_text_test "Unknown argument failure" \
  "$MAIN_SPEC" "Error: Unknown option '--non-existent-arg'." 1 \
  --api-key=SECRET --non-existent-arg

run_text_test "Value-taking arg requires a value" \
  "$MAIN_SPEC" "Error: Argument '--model' requires a value." 1 \
  --api-key SECRET --model

HELP_TEXT=$(cat <<'EOF'
A test script with various argument types.

Usage: [options]

Options:
  --api-key	The API key for authentication.
  --help	Show this help message and exit.
  --model	The model to use.
  --retries	Number of retries on failure.
  --stream	Enable streaming responses.
EOF
)

EXPECTED_HELP_JSON=$(jq -n --arg msg "$HELP_TEXT" '{help: $msg}')

run_json_test "Help generation" \
  "$MAIN_SPEC" "$EXPECTED_HELP_JSON" 0 \
  --help

# --- Stdin Test (Special Case) ---
echo "--- Running Test: Reads argument value from stdin when value is '-' ---"
STDIN_SPEC='{"content": {"type": "string", "required": true}}'
STDIN_ARGS=("--content" "-")
STDIN_DATA="This is a line from stdin."
EXPECTED_STDIN_OUTPUT='{"content": "This is a line from stdin."}'
script_to_test="${SCRIPT_REGISTRY[parse_args]}"
job_ticket=$(jq -n --argjson spec "$STDIN_SPEC" '{"spec": $spec, "args": $ARGS.positional}' --args -- "${STDIN_ARGS[@]}")
output=""
exit_code=0
set +e
output=$(echo "$STDIN_DATA" | bash "$script_to_test" "$job_ticket" 2>/dev/null)
exit_code=$?
set -e
expected_sorted=$(echo "$EXPECTED_STDIN_OUTPUT" | jq -S .)
output_sorted=$(echo "$output" | jq -S .)
if [[ "$exit_code" -eq 0 && "$output_sorted" == "$expected_sorted" ]]; then
  echo "PASS: Reads argument value from stdin when value is '-'"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: Stdin test failed."
  echo "  Exit Code: $exit_code (Expected 0)"
  echo "  Expected Output: $expected_sorted"
  echo "  Actual Output:   $output_sorted"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- SUMMARY ---
echo ""
echo "Test summary: $PASS_COUNT passed, $FAIL_COUNT failed."

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
