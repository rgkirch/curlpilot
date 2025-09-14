set -euo pipefail

# --- Configuration & Setup ---

# 1. Locate and source the real deps.bash.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

# 2. Use resolve_path to get the path to the real validate.js for the npm step.
VALIDATE_JS_PATH=$(resolve_path "ajv/validate.js")

# 3. Create a temporary directory for mock scripts and schemas.
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT # Cleanup on exit

# --- Test Harness ---

assert_success() {
  local description="$1"
  shift
  echo -n "🔹 Testing: $description..."
  if "$@"; then
    echo " ✅ PASSED"
  else
    echo " ❌ FAILED"
    exit 1
  fi
}

assert_failure() {
  local description="$1"
  shift
  echo -n "🔹 Testing: $description..."
  set +e
  local output
  output=$("$@" 2>&1)
  local exit_code=$?
  set -e
  if [[ $exit_code -ne 0 ]]; then
    echo " ✅ PASSED (failed as expected)"
  else
    echo " ❌ FAILED (was expected to fail but succeeded)"
    echo "--- Unexpected Output ---"
    echo "$output"
    echo "-----------------------"
    exit 1
  fi
}

# --- Test Cases ---

main() {
  echo "--- Running Final Integration Test ---"

  if [[ ! -f "$VALIDATE_JS_PATH" ]]; then
    echo "❌ Error: validate.js not found at '$VALIDATE_JS_PATH'" >&2
    exit 1
  fi

  echo "🔹 Ensuring 'ajv' dependency is installed..."
  (
    cd "$(dirname "$VALIDATE_JS_PATH")"
    if [[ ! -d "node_modules/ajv" ]]; then
        npm init -y >/dev/null 2>&1
        npm install ajv >/dev/null 2>&1
    fi
  )
  echo "🔹 Setup complete."

  # --- Test Case 1: Valid Output ---
  local valid_script_path="$TEST_DIR/valid_output.bash"
  local schema_for_valid_path="$TEST_DIR/valid_output.output.schema.json"

  cat > "$valid_script_path" <<'EOF'
#!/bin/bash
echo '{"status": "ok", "code": 200}'
EOF
  chmod +x "$valid_script_path"

  cat > "$schema_for_valid_path" <<'EOF'
{
  "type": "object",
  "properties": { "status": { "type": "string" }, "code": { "type": "integer" } },
  "required": ["status", "code"]
}
EOF

  register_dep "valid_output_test" "$valid_script_path"
  # FIX: Provide empty stdin to exec_dep using a here-string
  assert_success "script with valid output passes validation" \
    exec_dep "valid_output_test" <<< ""

  # --- Test Case 2: Invalid Output ---
  local invalid_script_path="$TEST_DIR/invalid_output.bash"
  local schema_for_invalid_path="$TEST_DIR/invalid_output.output.schema.json"

  cat > "$invalid_script_path" <<'EOF'
#!/bin/bash
echo '{"status": "ok", "code": "200"}'
EOF
  chmod +x "$invalid_script_path"

  cp "$schema_for_valid_path" "$schema_for_invalid_path"

  register_dep "invalid_output_test" "$invalid_script_path"
  # FIX: Provide empty stdin to exec_dep using a here-string
  assert_failure "script with invalid output fails validation" \
    exec_dep "invalid_output_test" <<< ""

  echo
  echo "🎉 All integration tests passed!"
}

main
