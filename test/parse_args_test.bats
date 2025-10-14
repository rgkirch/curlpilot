# test/parse_args_test.bats
#!/usr/bin/env bats

load test_helper.bash

  _run_parser() (
    source deps.bash
    set -euo pipefail

    local spec_json="$1"
    shift

    local job_ticket
    job_ticket=$(jq --null-input \
      --argjson spec "$spec_json" \
      '{"spec": $spec, "args": $ARGS.positional}' \
      --args -- "$@"
    )

    _exec_dep "$PROJECT_ROOT/src/parse_args/parse_args.bash" "parse_args" "$job_ticket"
  )

# ===============================================
# ==         SUCCESS TEST CASES                ==
# ===============================================

@test "Provides a value for a single required argument" {
  local spec='{"api_key": {"type": "string"}}'
  local expected='{"api_key": "SECRET"}'

  run --separate-stderr _run_parser "$spec" --api-key=SECRET

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Uses default value when argument is not provided" {
  local spec='{"model": {"type": "string", "default": "gpt-default"}}'
  local expected='{"model": "gpt-default"}'

  run --separate-stderr _run_parser "$spec" # No arguments provided

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Provided argument overrides default value" {
  local spec='{"model": {"type": "string", "default": "gpt-default"}}'
  local expected='{"model": "gpt-4"}'

  run --separate-stderr _run_parser "$spec" --model="gpt-4"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles key=value parsing" {
  local spec='{"api_key": {"type": "string"}}'
  local expected='{"api_key": "SECRET_VALUE"}'

  run --separate-stderr _run_parser "$spec" --api-key=SECRET_VALUE

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles key<space>value parsing" {
  local spec='{"api_key": {"type": "string"}}'
  local expected='{"api_key": "SECRET_VALUE"}'

  run --separate-stderr _run_parser "$spec" --api-key "SECRET_VALUE"

  assert_success
  assert_json_equal "$output" "$expected"
}


@test "Handles values containing an equals sign" {
  local spec='{"connection_string": {"type": "string"}}'
  local expected='{"connection_string": "user=admin;pass=123"}'

  run --separate-stderr _run_parser "$spec" --connection-string="user=admin;pass=123"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Standalone boolean flag is treated as true" {
  local spec='{"stream": {"type": "boolean", "default": false}}'
  local expected='{"stream": true}'

  run --separate-stderr _run_parser "$spec" --stream

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Boolean can be explicitly set to false" {
  local spec='{"stream": {"type": "boolean", "default": true}}'
  local expected='{"stream": false}'

  run --separate-stderr _run_parser "$spec" --stream=false

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Parses number type correctly" {
  local spec='{"retries": {"type": "number"}}'
  local expected='{"retries": 10}'

  run --separate-stderr _run_parser "$spec" --retries=10

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "String that looks like a number is kept as a string" {
  local spec='{"version": {"type": "string"}}'
  local expected='{"version": "1.0"}'

  run --separate-stderr _run_parser "$spec" --version=1.0

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Default value can be the string 'null'" {
  local spec='{"nullable_arg": {"type": "string", "default": "null"}}'
  local expected='{"nullable_arg": "null"}'

  run --separate-stderr _run_parser "$spec"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Duplicate arguments uses the last provided value" {
  local spec='{"api_key": {"type": "string"}}'
  local expected='{"api_key": "LAST_KEY"}'

  run --separate-stderr _run_parser "$spec" --api-key=FIRST_KEY --api-key=LAST_KEY

  assert_success
  assert_json_equal "$output" "$expected"
}

# ===============================================
# ==         -- TERMINATOR TESTS               ==
# ===============================================

@test "Handles -- to capture multiple subsequent words as an array" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["this", "is", "a", "test"]}'

  run --separate-stderr _run_parser "$spec" --message-content -- this is a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- to capture values that look like other options" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["this", "--is", "--a", "test"]}'

  run --separate-stderr _run_parser "$spec" --message-content -- this --is --a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- with a single quoted argument" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["a single quoted value"]}'

  run --separate-stderr _run_parser "$spec" --message-content -- "a single quoted value"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- correctly when other arguments are present" {
  local spec='{
    "model": {"type": "string"},
    "message_content": {"type": "array", "default": []}
  }'
  local expected='{"model": "gpt-4", "message_content": ["this", "is", "a", "test"]}'

  run --separate-stderr _run_parser "$spec" --model gpt-4 --message-content -- this is a test

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Handles -- with no subsequent values" {
  local spec='{"message_content": {"type": "array", "default": null}}'
  local expected='{"message_content": []}'

  run --separate-stderr _run_parser "$spec" --message-content --

  assert_success
  assert_json_equal "$output" "$expected"
}


# ===============================================
# ==         FAILURE TEST CASES                ==
# ===============================================

@test "Fails when a required argument is missing" {
  local spec='{"api_key": {"type": "string"}}'

  run --separate-stderr _run_parser "$spec" # No api_key provided

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Missing required value for key: api_key"
}

@test "Fails on an unknown argument" {
  local spec='{"api_key": {"type": "string"}}'

  run --separate-stderr _run_parser "$spec" --api-key=SECRET --non-existent-arg

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Unknown argument: --non-existent-arg"
}

@test "Fails when a value-taking argument receives no value" {
  local spec='{"model": {"type": "string"}}'

  run --separate-stderr _run_parser "$spec" --model

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Non-boolean argument --model requires a value"
}

@test "Correctly fails when a defined flag is used as a value" {
  local spec='{"command": {"type": "string"}, "version": {"type": "boolean"}}'

  run --separate-stderr _run_parser "$spec" --command --version

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Non-boolean argument --command requires a value"
}

@test "Fails when a non-numeric value is provided for a number type" {
  local spec='{"retries": {"type": "number"}}'

  run --separate-stderr _run_parser "$spec" --retries=five

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): string (\"five\") cannot be parsed as a number"
}

@test "Fails when invalid JSON is provided for a json type" {
  local spec='{"messages": {"type": "json"}}'
  local invalid_json='[{"role": "user"}'

  run --separate-stderr _run_parser "$spec" --messages="$invalid_json"

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Unfinished JSON term at EOF at line 1, column 17 (while parsing '[{\"role\": \"user\"}')"
}

@test "Fails when an invalid value is provided for a boolean type" {
  local spec='{"stream": {"type": "boolean"}}'

  run --separate-stderr _run_parser "$spec" --stream=yes

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): string (\"yes\") cannot be parsed as a boolean"
}

@test "Fails when a positional argument is provided" {
  local spec='{"api_key": {"type": "string"}}'

  run --separate-stderr _run_parser "$spec" --api-key=SECRET "some_file.txt"

  assert_failure
  assert_stderr --partial "jq: error (at <unknown>): Invalid argument (does not start with --): some_file.txt"
}

# ===============================================
# ==         SPECIAL TEST CASES                ==
# ===============================================

@test "Help generation" {
  local spec='{
    "_description": "A test script with various argument types.",
    "model": {"type": "string", "default": "gpt-default", "description": "The model to use."},
    "stream": {"type": "boolean", "default": true, "description": "Enable streaming responses."},
    "api_key": {"type": "string", "description": "The API key for authentication."},
    "retries": {"type": "number", "default": 3, "description": "Number of retries on failure."},
    "messages": {"type": "json", "default": [], "description": "A JSON array of messages."}
  }'
  local expected_output
  expected_output=$(printf '%b\n' \
    "A test script with various argument types." \
    "" \
    "USAGE:" \
    "  script.sh [OPTIONS]" \
    "" \
    "OPTIONS:" \
    "  --model\tThe model to use. (default: \"gpt-default\")" \
    "  --stream\tEnable streaming responses. (default: true)" \
    "  --api-key\tThe API key for authentication." \
    "  --retries\tNumber of retries on failure. (default: 3)" \
    "  --messages\tA JSON array of messages. (default: [])"
)

  run --separate-stderr _run_parser "$spec" --help

  assert_success
  assert_output '{"help_requested": true}'
  assert_stderr "$expected_output"
}

@test "--help is treated as a value when it appears after a -- terminator" {
  local spec='{"message_content": {"type": "array"}}'
  local expected='{"message_content": ["--help"]}'

  run --separate-stderr _run_parser "$spec" --message-content -- --help

  assert_success
  assert_json_equal "$output" "$expected"
  refute_stderr --partial "USAGE:"
}

@test "Reads string value from stdin when value is '-'" {
  local spec='{"content": {"type": "string"}}'
  local stdin_data="This is a line from stdin."
  local expected="{\"content\": \"${stdin_data}\"}"

  run --separate-stderr _run_parser "$spec" --content - <<< "$stdin_data"

  assert_success
  assert_json_equal "$output" "$expected"
}

@test "Reads JSON value from stdin when value is '-'" {
  local spec='{"messages": {"type": "json"}}'
  local stdin_data='[{"role": "user", "content": "hello"}]'
  local expected
  expected=$(jq -n --argjson data "$stdin_data" '{"messages": $data}')

  run --separate-stderr _run_parser "$spec" --messages - <<< "$stdin_data"

  assert_success
  assert_json_equal "$output" "$expected"
}

# ===============================================
# ==      SCHEMA VALIDATION TEST CASES         ==
# ===============================================

@test "Schema validation succeeds for valid JSON" {
  source deps.bash
  local mock_validator_path="$BATS_TEST_TMPDIR/mock_validator_success.bash"
  cat > "$mock_validator_path" <<'EOF'
#!/usr/bin/env bash
echo "Mock validator: Success!" >&2
exit 0
EOF
  chmod +x "$mock_validator_path"

  # Arrange: Inject the mock. This works because deps.bash was sourced in setup_file().
  mock_dep schema_validator.bash "$mock_validator_path"

  # Arrange: Create the schema file in the temp directory.
  local schema_path="$BATS_TEST_TMPDIR/body_schema.json"
  echo '{"type": "object"}' > "$schema_path"

  # Arrange: Define the argument spec, referencing the temporary schema file.
  local spec_with_schema
  spec_with_schema=$(jq -n --arg path "$schema_path" '{
    "body": { "type": "json", "schema": $path }
  }')

  local valid_json_body='{"model": "gpt-4"}'
  local expected="{\"body\": ${valid_json_body}}"

  # Act: The mock environment is inherited by the subshell created by `run`.
  run --separate-stderr _run_parser "$spec_with_schema" --body="$valid_json_body"

  # Assert
  assert_success
  assert_json_equal "$output" "$expected"
  assert_stderr --partial "Mock validator: Success!"
}

@test "Schema validation fails for invalid JSON" {
  source deps.bash
  # Arrange: Create a mock validator that always fails.
  local mock_validator_path="$BATS_TEST_TMPDIR/mock_validator_fail.bash"
  cat > "$mock_validator_path" <<'EOF'
#!/usr/bin/env bash
echo "Mock validator: Intentional failure." >&2
exit 1
EOF
  chmod +x "$mock_validator_path"

  # Arrange: Inject our failing mock.
  mock_dep schema_validator.bash "$mock_validator_path"

  # Arrange: Create the schema file.
  local schema_path="$BATS_TEST_TMPDIR/body_schema.json"
  echo '{"type": "object"}' > "$schema_path"

  # Arrange: Define the argument spec.
  local spec_with_schema
  spec_with_schema=$(jq -n --arg path "$schema_path" '{
    "body": { "type": "json", "schema": $path }
  }')

  local json_body='{"model": "any data is fine"}'

  # Act
  run --separate-stderr _run_parser "$spec_with_schema" --body="$json_body"

  # Assert
  assert_failure
  assert_stderr --partial "Mock validator: Intentional failure."
}
