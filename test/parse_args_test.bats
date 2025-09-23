# test/parse_args_test.bats

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
  job_ticket=$(jq --null-input \
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
    "description": "The API key for authentication."
  },
  "retries": {
    "type": "number",
    "default": 3,
    "description": "Number of retries on failure."
  },
  "messages": {
    "type": "json",
    "default": [],
    "description": "A JSON array of messages."
  }
}'

# ===============================================
# ==       SUCCESS TEST CASES        ==
# ===============================================

@test "All args provided" {
  expected='{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5, "messages": ["hello"]}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --model=gpt-4 --stream=false --retries=5 --messages='["hello"]'

  assert_success
  assert_json_equal "$output" "$expected"
}


@test "Argument with space" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 0, "messages": []}'
  run_parser "$MAIN_SPEC" --api-key SECRET --retries 0

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles key=value parsing without order-of-operations bug" {
  spec='{"api_key": {"type": "string"}}'
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
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3, "messages": []}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --stream

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Boolean can be explicitly set to false" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": false, "retries": 3, "messages": []}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --stream=false

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Number type is respected" {
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 10, "messages": []}'
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
  expected='{"api_key": "SECRET", "model": "gpt-default", "stream": true, "retries": 3, "messages": []}'
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

@test "Duplicate arguments uses the last provided value" {
  expected='{"api_key": "LAST_KEY", "model": "gpt-default", "stream": true, "retries": 3, "messages": []}'
  run_parser "$MAIN_SPEC" --api-key=FIRST_KEY --api-key=LAST_KEY

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Returns all default values when no arguments are provided" {
  local all_optional_spec='{
    "model": {"type": "string", "default": "default-model"},
    "stream": {"type": "boolean", "default": false}
  }'
  expected='{"model": "default-model", "stream": false}'

  run_parser "$all_optional_spec" # No arguments

  assert_success
  assert_json_equal "$output" "$expected"
}

# ===============================================
# ==         -- TERMINATOR TESTS             ==
# ===============================================

@test "Handles -- to capture multiple subsequent words as an array" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["this", "is", "a", "test"]}'

  run_parser "$spec" --message-content -- this is a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- to capture values that look like other options" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["this", "--is", "--a", "test"]}'

  run_parser "$spec" --message-content -- this --is --a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- with a single quoted argument" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["a single quoted value"]}'

  run_parser "$spec" --message-content -- "a single quoted value"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- correctly when other arguments are present" {
  local spec='{
    "model": {"type": "string"},
    "message_content": {"type": "array", "default": []}
  }'
  local expected='{"model": "gpt-4", "message_content": ["this", "is", "a", "test"]}'

  run_parser "$spec" --model gpt-4 --message-content -- this is a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- with no subsequent values" {
  local spec='{"message_content": {"type": "array", "default": null}}'
  local expected='{"message_content": []}'

  run_parser "$spec" --message-content --

  assert_success
  assert_json_equal "$output" "$expected"
}


# ===============================================
# ==       FAILURE TEST CASES        ==
# ===============================================

@test "Fails when a required argument is missing" {
  # api_key is required because it has no default.
  run_parser "$MAIN_SPEC" --model=gpt-4

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Missing required value for key: api_key"
}

@test "Fails on an unknown argument" {
  run_parser "$MAIN_SPEC" --api-key=SECRET --non-existent-arg

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Unknown argument: --non-existent-arg"
}

@test "Fails when a value-taking argument receives no value" {
  run_parser "$MAIN_SPEC" --api-key SECRET --model

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Non-boolean argument --model requires a value"
}

@test "Correctly fails when a defined flag is used as a value" {
  spec='{"command": {"type": "string"}, "version": {"type": "boolean"}}'
  run_parser "$spec" --command --version --version

  assert_failure

  # 1. Define the exact error you expect.
  local expected_error="jq: error (at <unknown>): Non-boolean argument --command requires a value"

  # 2. Filter the actual stderr to remove debug lines.
  #    The 'grep -v' command excludes lines matching the pattern.
  local filtered_stderr
  filtered_stderr=$(echo "$stderr" | grep -v '\["DEBUG:"')

  # 3. Assert that the filtered output is exactly what you expect.
  [ "$filtered_stderr" = "$expected_error" ]
}

@test "Fails when a non-numeric value is provided for a number type" {
  # 'five' is not a valid number.
  run_parser "$MAIN_SPEC" --api-key=SECRET --retries=five

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): string (\"five\") cannot be parsed as a number"
}

@test "Fails when invalid JSON is provided for a json type" {
  # This is not a valid JSON array.
  local invalid_json='[{"role": "user"}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --messages="$invalid_json"

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Unfinished JSON term at EOF at line 1, column 17 (while parsing '[{\"role\": \"user\"}')"
}

@test "Fails when an invalid value is provided for a boolean type" {
  # 'yes' is not a valid boolean according to the script's likely logic (true/false).
  run_parser "$MAIN_SPEC" --api-key=SECRET --stream=yes

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): string (\"yes\") cannot be parsed as a boolean"
}

@test "Fails when a positional argument is provided" {
  # "some_file.txt" is a positional argument and should be rejected.
  run_parser "$MAIN_SPEC" --api-key=SECRET "some_file.txt"

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Invalid argument (does not start with --): some_file.txt"
}

# ===============================================
# ==       SPECIAL TEST CASES        ==
# ===============================================

@test "Help generation" {
  expected_output=$(printf '%b\n' \
    "A test script with various argument types." \
    "" \
    "USAGE:" \
    "  script.sh [OPTIONS]" \
    "" \
    "OPTIONS:" \
    "  --model\tThe model to use. (default: \"gpt-default\")" \
    "  --stream\tEnable streaming responses. (default: true)" \
    "  --api-key\tThe API key for authentication. " \
    "  --retries\tNumber of retries on failure. (default: 3)" \
    "  --messages\tA JSON array of messages. (default: [])"
)

  run_parser "$MAIN_SPEC" --help

  assert_success
  # The new help logic prints {} to stdout and the help text to stderr.
  assert_output '{"help_requested": true}'
  assert_stderr "$expected_output"
}

@test "--help is treated as a value when it appears after a -- terminator" {
  # Arrange: A spec for an argument that can take multiple values.
  local spec='{"message_content": {"type": "array"}}'
  # Expected: The parser should treat "--help" as a string value for message_content.
  local expected='{"message_content": ["--help"]}'

  # Act: Run the parser.
  run_parser "$spec" --message-content -- --help

  # Assert
  assert_success
  assert_json_equal "$output" "$expected"
  # Also assert that the help text was NOT printed to stderr.
  refute_stderr --partial "USAGE:"
}

@test "Reads string value from stdin when value is '-'" {
  spec='{"content": {"type": "string"}}'

  local stdin_data="This is a line from stdin."
  local expected="{\"content\": \"${stdin_data}\"}"

  local job_ticket
  job_ticket=$(jq --null-input \
    --argjson spec "$spec" \
    '{"spec": $spec, "args": $ARGS.positional}' \
    --args -- --content -
  )

  # Use process substitution to provide stdin without putting `run` in a subshell.
  # The `<` redirects stdin from the output of the `printf` command.
  run --separate-stderr bash "$SCRIPT_TO_TEST" "$job_ticket" < <(printf "%s" "$stdin_data")

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Reads JSON value from stdin when value is '-'" {
  # Arrange: Define the core test data as compact JSON strings.
  local compact_stdin_data='[{"role": "user", "content": "hello"}]'
  local expected_base_json='{"api_key":"SECRET","model":"gpt-default","stream":true,"retries":3}'

  # Arrange: Use jq's identity filter (.) to pretty-print the compact string for stdin.
  local stdin_data
  stdin_data=$(jq --compact-output . <<< "$compact_stdin_data")

  # Arrange: Use jq to safely build the final expected JSON object.
  # This is more robust than using a shell here-document.
  local expected
  expected=$(jq --null-input \
    --argjson stdin "$compact_stdin_data" \
    --argjson base "$expected_base_json" \
    '$base + {messages: $stdin}')

  # Act: Run the parser, piping the pretty-printed data to stdin via a here-string.
  run_parser "$MAIN_SPEC" --api-key=SECRET --messages - <<< "$stdin_data"

  # Assert
  assert_success
  assert_json_equal "$output" "$expected"
}
