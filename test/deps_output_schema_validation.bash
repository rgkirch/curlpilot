#!/bin/bash
#
# Tests deps.bash "in place" and creates a robust, temporary validator
# to ensure correct paths are used during the test.
#
set -euo pipefail

# --- Configuration & Setup ---

# 1. Locate and source deps.bash FIRST.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

# 2. Use the new functions to define the path to the real validate.js.
VALIDATE_JS_PATH=$(resolve_path "ajv/validate.js")

# 3. Create a temporary directory for mocks and the temp validator.
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT # Cleanup on exit

# --- Create a TEST-SPECIFIC validator wrapper ---
# This wrapper is guaranteed to call the REAL validate.js with the correct path,
# bypassing any path bugs in the project's actual schema_validator.bash.
cat > "$TEST_DIR/schema_validator.bash" <<EOF
#!/bin/bash
set -euo pipefail
schema_path="\$1"
input=\$(cat)
if [[ -z "\$input" ]]; then
    echo "Error: Standard input was empty" >&2
    exit 1
fi
# Directly execute the REAL validate.js script using its absolute path
exec node "$VALIDATE_JS_PATH" "\$schema_path" <(echo "\$input")
EOF
chmod +x "$TEST_DIR/schema_validator.bash"

# 4. Point deps.bash to our temporary directory to find the validator.
SCRIPT_REGISTRY_DIR="$TEST_DIR"

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
  "$@"
  local exit_code=$?
  set -e
  if [[ $exit_code -ne 0 ]]; then
    echo " ✅ PASSED (failed as expected)"
  else
    echo " ❌ FAILED (was expected to fail but succeeded)"
    exit 1
  fi
}

# --- Test Cases ---

main() {
  echo "--- Running Refactored In-Place Validation Tests ---"

  # Check that validate.js exists before starting.
  if [[ ! -f "$VALIDATE_JS_PATH" ]]; then
    echo "❌ Error: validate.js not found at '$VALIDATE_JS_PATH'" >&2
    exit 1
  fi

  # --- Prepare Dependencies for the REAL validate.js ---
  echo "🔹 Ensuring 'ajv' dependency is installed for validate.js..."
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
  assert_success "script with valid output passes validation" \
    exec_dep "valid_output_test"

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
  assert_failure "script with invalid output fails validation" \
    exec_dep "invalid_output_test"

  echo
  echo "🎉 All refactored validation tests passed!"
}

main
