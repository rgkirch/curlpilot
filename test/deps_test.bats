#!/usr/bin/env bats

setup() {
  # Source the real helpers, which will define the REAL project root.
  source "$(dirname "$BATS_TEST_FILENAME")/test_helper.bash"

  # Source the script-under-test using the correct wrapper.
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"

  # Create a sandbox for our temporary scripts.
  SANDBOX_DIR="$BATS_TEST_TMPDIR/sandbox"
  mkdir -p "$SANDBOX_DIR"

  # Failsafe: Ensure the sandbox is in a temporary directory.
  if [[ ! "$SANDBOX_DIR" == /tmp/* ]]; then
    echo "FATAL: Sandbox directory is not under /tmp. Aborting." >&2
    exit 1
  fi

  # Create a placeholder for the real src directory so mock_dep's
  # existence check on the original file passes.
  mkdir -p "$PROJECT_ROOT/src"
}

teardown() {
  echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
  find "$BATS_TEST_TMPDIR" -type f -print0 | xargs -0 head &> /dev/fd/3 || true
}

# --- Sandboxed Helper Functions ---

create_sandboxed_dep() {
  local name="$1"
  local content="$2"
  local script_path="$SANDBOX_DIR/${name}.bash"
  mkdir -p "$(dirname "$script_path")"
  echo "#!/usr/bin/env bash" > "$script_path"
  echo "$content" >> "$script_path"
  chmod +x "$script_path"
  echo "$script_path" # Return the absolute path to the script
}

create_sandboxed_schema() {
  local name="$1"
  local content="$2"
  local schema_path="$SANDBOX_DIR/${name}.schema.json"
  mkdir -p "$(dirname "$schema_path")"
  echo "$content" > "$schema_path"
}


@test "exec_dep: basic execution with stdout and stderr" {
  local script_path
  script_path=$(create_sandboxed_dep "basic" 'echo "to stdout"; echo "to stderr" >&2')
  touch "$PROJECT_ROOT/src/basic.bash" # Placeholder for mock_dep check

  mock_dep "basic.bash" "$script_path"
  register_dep "basic_key" "basic.bash"

  run --separate-stderr exec_dep "basic_key"
  assert_success
  assert_output "to stdout"
  assert_stderr "to stderr"
}

@test "exec_dep: passes arguments correctly" {
  local script_path
  script_path=$(create_sandboxed_dep "args" 'echo "Args: $@"')
  touch "$PROJECT_ROOT/src/args.bash"

  mock_dep "args.bash" "$script_path"
  register_dep "args_key" "args.bash"

  run --separate-stderr exec_dep "args_key" "hello" "world with spaces"
  assert_success
  assert_output "Args: hello world with spaces"
}

@test "exec_dep: propagates non-zero exit code from dependency" {
  local script_path
  script_path=$(create_sandboxed_dep "fail" 'echo "something went wrong" >&2; exit 42')
  touch "$PROJECT_ROOT/src/fail.bash"

  mock_dep "fail.bash" "$script_path"
  register_dep "fail_key" "fail.bash"

  run --separate-stderr exec_dep "fail_key"
  assert_failure 42
  assert_stderr --partial "something went wrong"
}

@test "exec_dep: enables tracing and creates trace files" {
  export CURLPILOT_TRACE=true
  local script_path
  script_path=$(create_sandboxed_dep "trace_me" 'echo "tracing stdout"')
  touch "$PROJECT_ROOT/src/trace_me.bash"

  mock_dep "trace_me.bash" "$script_path"
  register_dep "trace_key" "trace_me.bash"

  run --separate-stderr exec_dep "trace_key" "arg1" "arg with spaces"
  assert_success

  local trace_path
  trace_path=$(find "$CURLPILOT_TRACE_ROOT_DIR" -type d -name '*_trace_key' 2>/dev/null)
  assert_exists "$trace_path"
  assert_file_exists "${trace_path}/args.json"

  local args_json
  args_json=$(jq -c . "${trace_path}/args.json")
  assert_equal "$args_json" '["arg1","arg with spaces"]'
}

@test "exec_dep: validates stdout against a schema (success)" {
  local script_path
  script_path=$(create_sandboxed_dep "valid_json" 'echo "{\"name\": \"test\"}"')
  create_sandboxed_schema "valid_json.stdout" '{ "type": "object" }'
  touch "$PROJECT_ROOT/src/valid_json.bash"

  mock_dep "valid_json.bash" "$script_path"
  register_dep "valid_key" "valid_json.bash"

  run --separate-stderr exec_dep "valid_key"
  assert_success
}

@test "exec_dep: validates stdout against a schema (failure)" {
  local script_path
  script_path=$(create_sandboxed_dep "invalid_json" 'echo "this is not json"')
  create_sandboxed_schema "invalid_json.stdout" '{ "type": "object" }'
  touch "$PROJECT_ROOT/src/invalid_json.bash"

  mock_dep "invalid_json.bash" "$script_path"
  register_dep "invalid_key" "invalid_json.bash"

  run --separate-stderr exec_dep "invalid_key"
  assert_failure 1
  assert_stderr --partial "The 'stdout' of 'invalid_key' failed schema validation"
}

@test "exec_dep: validates stderr against a schema (failure)" {
  local script_path
  script_path=$(create_sandboxed_dep "stderr_validation" 'echo "OK"; echo "not json" >&2')
  create_sandboxed_schema "stderr_validation.stderr" '{ "type": "object" }'
  touch "$PROJECT_ROOT/src/stderr_validation.bash"

  mock_dep "stderr_validation.bash" "$script_path"
  register_dep "stderr_key" "stderr_validation.bash"

  run --separate-stderr exec_dep "stderr_key"
  assert_failure 1
  assert_stderr --partial "The 'stderr' of 'stderr_key' failed schema validation"
}

@test "mock_dep: successfully overrides with a relative path" {
  # This test specifically checks the original, relative-path behavior of mock_dep.
  mkdir -p "$PROJECT_ROOT/test/mock"
  local mock_path="$PROJECT_ROOT/test/mock/mock_version.bash"
  echo '#!/usr/bin/env bash' > "$mock_path"
  echo 'echo "I am the mock"' >> "$mock_path"
  chmod +x "$mock_path"

  touch "$PROJECT_ROOT/src/original.bash"

  mock_dep "original.bash" "mock/mock_version.bash"
  register_dep "my_key" "original.bash"

  run --separate-stderr exec_dep "my_key"
  assert_success
  assert_output "I am the mock"

  # Clean up the files created in the real project dir
  rm "$mock_path"
  rm "$PROJECT_ROOT/src/original.bash"
}
