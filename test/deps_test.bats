#!/usr/bin/env bats
# test/deps_test.bats

# Load deps.bash FIRST to get helper functions like resolve_path.
source deps.bash
# Load the test helper AFTER deps.bash.
source "$(dirname "$BATS_TEST_FILENAME")/test_helper.bash"

_setup() {
  # Re-source deps.bash within the test's context to reset SCRIPT_REGISTRY
  # and ensure it uses the sandboxed PROJECT_ROOT.
  source deps.bash

  local REAL_PROJECT_ROOT="$PROJECT_ROOT"
  local SANDBOX_ROOT="$BATS_TEST_TMPDIR/sandbox"
  local SANDBOX_SRC_DIR="$SANDBOX_ROOT/src"

  # 1. Create sandbox directory structure
  mkdir -p "$SANDBOX_SRC_DIR"
  mkdir -p "$SANDBOX_ROOT/test/mock"

  # 2. Create a mock logging.bash in the sandbox.
  cat > "$SANDBOX_SRC_DIR/logging.bash" <<'EOF'
log_error() { echo "ERROR: $@"; } # Don't send to stderr in tests
log_info() { echo "INFO: $@"; }
log_debug() { echo "DEBUG: $@"; }
log_warn() { echo "WARN: $@"; }
EOF

  # 3. Create a MOCK schema_validator.bash in the sandbox.
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

  if [[ "${BATS_TEST_DESCRIPTION}" == *"tracing"* ]]; then
    export CURLPILOT_TRACE=true
    export CURLPILOT_TRACE_ROOT_DIR="$BATS_TEST_TMPDIR/curlpilot-trace"
    mkdir -p "$CURLPILOT_TRACE_ROOT_DIR"
    local suite_id="bats_$(basename "$BATS_TEST_FILENAME" .bats)"
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
    mkdir -p "$suite_path"
    export CURLPILOT_TRACE_PATH="$suite_path"
  fi

  log_debug "setup done"
}

# Asserts that a specific field in a JSON input matches an expected value.
# Usage: assert_json_value <json_string> <jq_query> <expected_value>
assert_json_value() {
  local json_string="$1"
  local jq_query="$2"
  local expected_value="$3"
  local actual_value

  # Run jq, capturing output and status. The -e flag sets exit status based on output.
  # The query should produce a single JSON primitive (string, number, bool, null).
  # We remove surrounding quotes for string comparison.
  if ! actual_value=$(echo "$json_string" | jq -e "$jq_query" | sed 's/^"\(.*\)"$/\1/'); then
    echo "FAIL: jq query '$jq_query' failed or produced no output." >&3
    echo "Input JSON:" >&3
    echo "$json_string" >&3
    return 1
  fi

  if [[ "$actual_value" != "$expected_value" ]]; then
    echo "FAIL: JSON value mismatch for query '$jq_query'." >&3
    echo "Expected: '$expected_value'" >&3
    echo "Actual  : '$actual_value'" >&3
    echo "Input JSON:" >&3
    echo "$json_string" >&3
    return 1
  fi
  # Implicit success if we reach here
  return 0
}

# --- Sandboxed Helper Functions ---
create_dep_script() {
  local name="$1"
  local content="$2"
  local script_path="$PROJECT_ROOT/src/${name}.bash"
  echo "#!/usr/bin/env bash" > "$script_path"
  echo "set -euo pipefail" >> "$script_path" # Good practice for test scripts
  echo "$content" >> "$script_path"
  chmod +x "$script_path"
}

create_mock_script() {
  local name="$1"
  local content="$2"
  local script_path="$PROJECT_ROOT/test/mock/${name}.bash"
  echo "#!/usr/bin/env bash" > "$script_path"
  echo "set -euo pipefail" >> "$script_path"
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
  create_dep_script "basic" 'echo "I am the original"'
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
  create_dep_script "trace_me" "original"
  create_mock_script "trace_mock" 'echo "tracing stdout"'

  mock_dep "trace_me.bash" "mock/trace_mock.bash"
  register_dep "trace_key" "trace_me.bash"

  run --separate-stderr exec_dep "trace_key" "arg1" "arg with spaces"
  assert_success

  # Find the directory created by _exec_dep
  local dep_trace_path
  dep_trace_path=$(find "$CURLPILOT_TRACE_ROOT_DIR" -type d -name '*_trace_key' 2>/dev/null | head -n 1)
  assert_exists "$dep_trace_path"

  # CORRECTED: Check for record.ndjson
  local record_file="${dep_trace_path}/record.ndjson"
  assert_file_exists "$record_file"

  # CORRECTED: Verify key fields in the record
  run jq '.' "$record_file"
  assert_success # Ensure jq parsing worked
  assert_output --partial '"name": "trace_key"'
  assert_output --partial '"parentId": "bats_deps_test/4"' # Assuming this is test #4
  assert_output --partial '"exit_code": 0'
  assert_output --partial '"wall_duration_us":'
  assert_output --partial '"cpu_duration_us":'
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
  # CORRECTED: Expect exit code 124 for schema failure
  assert_failure 124
  assert_stderr --partial "The 'stdout' of 'invalid_key' failed schema validation"
  assert_stderr --partial "Mock Validator: Invalid JSON" # Check mock output too
}

@test "exec_dep: validates stderr against a schema (failure)" {
  create_dep_script "stderr_validation" 'echo "OK"; echo "not json" >&2'
  create_stderr_schema "stderr_validation" '{ "type": "object" }'

  register_dep "stderr_key" "stderr_validation.bash"

  run --separate-stderr exec_dep "stderr_key"
  # CORRECTED: Expect exit code 124 for schema failure
  assert_failure 124
  assert_stderr --partial "The 'stderr' of 'stderr_key' failed schema validation"
  assert_stderr --partial "Mock Validator: Invalid JSON"
}

@test "mock_dep: successfully overrides with a relative path" {
  create_dep_script "original" "echo 'I am the original'" # Added echo
  create_mock_script "mock_version" "echo 'I am the mock'"

  mock_dep "original.bash" "mock/mock_version.bash"
  register_dep "my_key" "original.bash"

  run --separate-stderr exec_dep "my_key"
  assert_success
  assert_output "I am the mock"
}

@test "exec_dep: tracing a command that fails" {
  create_dep_script "fail_script" 'echo "Error output" >&2; exit 55'
  register_dep "fail_key" "fail_script.bash"

  run --separate-stderr exec_dep "fail_key"
  assert_failure 55 # Check the propagated exit code

  # Find the trace directory for this specific execution
  local dep_trace_path
  dep_trace_path=$(find "$CURLPILOT_TRACE_ROOT_DIR" -type d -name '*_fail_key' 2>/dev/null | head -n 1)
  assert_exists "$dep_trace_path"

  local record_file="${dep_trace_path}/record.ndjson"
  local rusage_file="${dep_trace_path}/rusage"
  local stderr_file="${dep_trace_path}/stderr"

  assert_file_exists "$record_file"
  assert_file_exists "$rusage_file"
  assert_file_exists "$stderr_file"

  # 1. Verify rusage file IS valid JSON (because -q suppressed errors)
  run jq '.' "$rusage_file"
  assert_success # Should now parse cleanly
  assert_output --partial '"user_cpu_seconds":' # Quick check

  # 2. Verify stderr file captured script's error output
  assert_file_contains "$stderr_file" "Error output"

  # 3. Verify record.ndjson file content using the helper
  local record_json
  record_json=$(cat "$record_file") # Read the JSON content once

  assert_json_value "$record_json" '.name' "fail_key"

  # --- CORRECTED ASSERTION ---
  # Dynamically construct the expected parent ID using the current test number
  local expected_parent_id="bats_deps_test/${BATS_TEST_NUMBER}"
  assert_json_value "$record_json" '.parentId' "$expected_parent_id"
  # --- END CORRECTION ---

  assert_json_value "$record_json" '.data.exit_code' "55"

  # Check that rusage fields ARE populated (even if 0)
  assert_json_value "$record_json" '.data.user_cpu_seconds' "0.00"
  assert_json_value "$record_json" '.data.cpu_duration_us' "0"
  # Check existence of another field using jq's 'has'
  run jq -e 'has("data") and (.data | has("max_rss_kb"))' "$record_file"
  assert_success "Record should contain data.max_rss_kb field"
}
