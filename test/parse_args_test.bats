#!/usr/bin/env bats

# Load the helper file at the top. Its setup_file() function will run
# automatically by Bats before any tests start.
load 'test_helper'

# This function runs before EACH test in a separate shell process.
setup() {
  # Source your project's dependency script to make its functions available.
  # This provides the `register_dep` command for this test's process.
  source "$PROJECT_ROOT/deps.bash"

  # Now you can safely call your project's functions.
  register_dep "parse_args" "parse_args.bash"
  SCRIPT_TO_TEST="${SCRIPT_REGISTRY[parse_args]}"
}

# --- HELPER FUNCTION ---
run_parser() {
  local spec="$1"
  shift
  local job_ticket
  job_ticket=$(jq -n \
    --argjson spec "$spec" \
    '{"spec": $spec, "args": $ARGS.positional}' \
    --args -- "$@"
  )
  run --separate-stderr bash "$SCRIPT_TO_TEST" "$job_ticket"
}

# --- GLOBAL TEST DATA ---
MAIN_SPEC='{
  "_description": "A test script with various argument types.",
  "model": {
    "type": "string",
    "default": "gpt-default",
    "description": "The model to use."
  },
  "stream": {
    "type": "boolean",
    "default": true,
    "description": "Enable streaming responses."
  },
  "api_key": {
    "type": "string",
    "required": true,
    "description": "The API key for authentication."
  },
  "retries": {
    "type": "number",
    "default": 3,
    "description": "Number of retries on failure."
  }
}'

# ===============================================
# ==           SUCCESS TEST CASES            ==
# ===============================================

@test "All args provided" {
  expected='{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --model=gpt-4 --stream=false --retries=5

  assert_success
  assert_json_equal "$output" "$expected"
}

#bats test_tags=bats:focus
@test "Argument with space" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0}'
  run_parser "$MAIN_SPEC" --api-key SECRET --retries 0

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles key=value parsing without order-of-operations bug" {
  spec='{"api_key": {"type": "string", "required": true}}'
  expected='{"api_key": "SECRET_VALUE"}'
  run_parser "$spec" --api-key=SECRET_VALUE

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles values containing an equals sign" {
  spec='{"connection_string": {"type": "string"}}'
  expected='{"connection_string": "user=admin;pass=123"}'
  run_parser "$spec" --connection-string="user=admin;pass=123"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Standalone boolean flag is treated as true" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --stream

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Boolean can be explicitly set to false" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --stream=false

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Number type is respected" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --retries=10

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "String that looks like a number is still a string" {
  spec='{"version": {"type": "string"}}'
  expected='{"version": "1.0"}'
  run_parser "$spec" --version=1.0

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Defaults are applied correctly" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3}'
  run_parser "$MAIN_SPEC" --api-key=SECRET

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Default value can be the string 'null'" {
  spec='{"nullable_arg": {"type": "string", "default": "null"}}'
  expected='{"nullable_arg": "null"}'
  run_parser "$spec" # No arguments, should use default

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Default does not override a passed value" {
  spec='{"config": {"type": "json", "default": {"theme": "dark", "user": "guest"}}}'
  expected='{"config": {"user":"admin"}}'
  run_parser "$spec" --config='{"user":"admin"}'

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Correctly handles a value that looks like a flag" {
  spec='{"command": {"type": "string"}, "version": {"type": "boolean"}}'
  expected='{"command": "--version"}'
  run_parser "$spec" --command '--version'

  assert_success
  assert_json_equal "$output" "$expected"
}

# ===============================================
# ==           FAILURE TEST CASES            ==
# ===============================================

@test "Fails when a required argument is missing" {
  run_parser "$MAIN_SPEC" --model=gpt-4

  assert_failure
  assert_output --partial "Error: Required argument '--api-key' is missing."
}

@test "Fails on an unknown argument" {
  run_parser "$MAIN_SPEC" --api-key=SECRET --non-existent-arg

  assert_failure
  assert_output --partial "Error: Unknown option '--non-existent-arg'."
}

@test "Fails when a value-taking argument receives no value" {
  run_parser "$MAIN_SPEC" --api-key SECRET --model

  assert_failure
  assert_output --partial "Error: Argument '--model' requires a value."
}

# ===============================================
# ==          SPECIAL TEST CASES             ==
# ===============================================

@test "Help generation" {
  # Use a heredoc for cleaner multi-line strings
  read -r -d '' help_text <<'EOF' || true
A test script with various argument types.

Usage: [options]

Options:
  --api-key The API key for authentication.
  --help  Show this help message and exit.
  --model The model to use.
  --retries Number of retries on failure.
  --stream  Enable streaming responses.
EOF
  expected_json=$(jq -n --arg msg "$help_text" '{help: $msg}')

  run_parser "$MAIN_SPEC" --help

  assert_success
  assert_json_equal "$output" "$expected_json"
}

@test "Reads argument value from stdin when value is '-'" {
  spec='{"content": {"type": "string", "required": true}}'
  expected='{"content": "This is a line from stdin."}'

  job_ticket=$(jq -n --argjson spec "$spec" '{"spec": $spec, "args": ["--content", "-"]}')

  # Pipe data into the script and capture its output with 'run'
  run --separate-stderr bash -c "echo 'This is a line from stdin.' | bash '$SCRIPT_TO_TEST' '$job_ticket'"

  assert_success
  assert_json_equal "$output" "$expected"
}
