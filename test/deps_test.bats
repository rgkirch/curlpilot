#!/usr/bin/env bats

# Source the global test helper, which provides the setup() and teardown() hooks.
source "$(dirname "$BATS_TEST_FILENAME")/test_helper.bash"

# This test-specific setup function will be called automatically by the global setup().
_setup() {
  local REAL_PROJECT_ROOT="$PROJECT_ROOT"
  local SANDBOX_ROOT="$BATS_TEST_TMPDIR/sandbox"
  local SANDBOX_SRC_DIR="$SANDBOX_ROOT/src"

  # 1. Create sandbox directory structure
  mkdir -p "$SANDBOX_SRC_DIR"
  mkdir -p "$SANDBOX_ROOT/test/mock"

  # 2. Create a mock logging.bash in the sandbox.
  # This makes deps.bash work without needing the real logging script.
  cat > "$SANDBOX_SRC_DIR/logging.bash" <<'EOF'
log_error() { echo "ERROR: $@" >&2; }
log_info() { echo "INFO: $@" >&2; }
log_debug() { echo "DEBUG: $@" >&2; }
log_warn() { echo "WARN: $@" >&2; }
EOF

  # 3. Create a MOCK schema_validator.bash in the sandbox.
  # This removes the dependency on Node.js and ajv for our tests.
  cat > "$SANDBOX_SRC_DIR/schema_validator.bash" <<'EOF'
#!/usr/bin/env bash
# Mock schema validator. The schema file argument ($1) is ignored.
# It just checks if stdin is valid JSON.
if ! jq -e . >/dev/null 2>&1; then
    echo "Mock Validator: Invalid JSON" >&2
    exit 1
fi
exit 0
EOF
  chmod +x "$SANDBOX_SRC_DIR/schema_validator.bash"


  # 4. NOW, HIJACK PROJECT_ROOT for the test's execution context.
  export PROJECT_ROOT="$SANDBOX_ROOT"

  # Failsafe: Ensure the sandbox is in a temporary directory.
  if [[ ! "$PROJECT_ROOT" == /tmp/* ]]; then
    echo "FATAL: Sandbox directory is not under /tmp. Aborting." >&2
    exit 1
  fi
}

# --- Sandboxed Helper Functions ---
create_dep_script() {
  local name="$1"
  local content="$2"
  local script_path="$PROJECT_ROOT/src/${name}.bash"
  echo "#!/usr/bin/env bash" > "$script_path"
  echo "$content" >> "$script_path"
  chmod +x "$script_path"
}

create_mock_script() {
  local name="$1"
  local content="$2"
  local script_path="$PROJECT_ROOT/test/mock/${name}.bash"
  echo "#!/usr/bin/env bash" > "$script_path"
  echo "$content" >> "$script_path"
  chmod +x "$script_path"
}

create_schema() {
  local name="$1"
  local content="$2"
  local schema_path="$PROJECT_ROOT/src/${name}.stdout.schema.json"
  echo "$content" > "$schema_path"
}

create_stderr_schema() {
  local name="$1"
  local content="$2"
  local schema_path="$PROJECT_ROOT/src/${name}.stderr.schema.json"
  echo "$content" > "$schema_path"
}


@test "exec_dep: basic execution with stdout and stderr" {
  create_dep_script "basic" "I am the original"
  create_mock_script "basic_mock" 'echo "to stdout"; echo "to stderr" >&2'

  mock_dep "basic.bash" "mock/basic_mock.bash"
  register_dep "basic_key" "basic.bash"

  run --separate-stderr exec_dep "basic_key"
  assert_success
  assert_output "to stdout"
  assert_stderr "to stderr"
}

@test "exec_dep: passes arguments correctly" {
  create_dep_script "args" "original"
  create_mock_script "args_mock" 'echo "Args: $@"'

  mock_dep "args.bash" "mock/args_mock.bash"
  register_dep "args_key" "args.bash"

  run --separate-stderr exec_dep "args_key" "hello" "world with spaces"
  assert_success
  assert_output "Args: hello world with spaces"
}

@test "exec_dep: propagates non-zero exit code from dependency" {
  create_dep_script "fail" "original"
  create_mock_script "fail_mock" 'echo "something went wrong" >&2; exit 42'

  mock_dep "fail.bash" "mock/fail_mock.bash"
  register_dep "fail_key" "fail.bash"

  run --separate-stderr exec_dep "fail_key"
  assert_failure 42
  assert_stderr --partial "something went wrong"
}

@test "exec_dep: enables tracing and creates trace files" {
  export CURLPILOT_TRACE=true
  # Re-source deps.bash AFTER setting the trace variable to trigger init logic.
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"

  create_dep_script "trace_me" "original"
  create_mock_script "trace_mock" 'echo "tracing stdout"'

  mock_dep "trace_me.bash" "mock/trace_mock.bash"
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
  create_dep_script "valid_json" 'echo "{\"name\": \"test\"}"'
  create_schema "valid_json" '{ "type": "object" }'

  register_dep "valid_key" "valid_json.bash"

  run --separate-stderr exec_dep "valid_key"
  assert_success
}

@test "exec_dep: validates stdout against a schema (failure)" {
  create_dep_script "invalid_json" 'echo "this is not json"'
  create_schema "invalid_json" '{ "type": "object" }'

  register_dep "invalid_key" "invalid_json.bash"

  run --separate-stderr exec_dep "invalid_key"
  assert_failure 1
  assert_stderr --partial "The 'stdout' of 'invalid_key' failed schema validation"
}

@test "exec_dep: validates stderr against a schema (failure)" {
  create_dep_script "stderr_validation" 'echo "OK"; echo "not json" >&2'
  create_stderr_schema "stderr_validation" '{ "type": "object" }'

  register_dep "stderr_key" "stderr_validation.bash"

  run --separate-stderr exec_dep "stderr_key"
  assert_failure 1
  assert_stderr --partial "The 'stderr' of 'stderr_key' failed schema validation"
}

@test "mock_dep: successfully overrides with a relative path" {
  create_dep_script "original" "I am the original"
  create_mock_script "mock_version" "echo 'I am the mock'"

  mock_dep "original.bash" "mock/mock_version.bash"
  register_dep "my_key" "original.bash"

  run --separate-stderr exec_dep "my_key"
  assert_success
  assert_output "I am the mock"
}
