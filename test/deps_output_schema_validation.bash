#!/bin/bash
#
# An INTEGRATION TEST to verify that deps.bash and the real validate.js
# work together correctly for output schema validation.
#
set -euo pipefail

# --- Configuration ---

# 1. Set the root of your project directory.
TEST_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(dirname "$TEST_SCRIPT_DIR")"

# 2. DEFINE THE PATHS to the REAL scripts we are testing.
#    Confirm these paths are correct for your environment.
DEPS_BASH_PATH="$PROJECT_ROOT/deps.bash"
VALIDATE_JS_PATH="$PROJECT_ROOT/ajv/validate.js"
SCHEMA_VALIDATOR_BASH_PATH="$PROJECT_ROOT/schema_validator.bash"

# --- Test Setup ---

# Check that the necessary files exist before starting.
if [[ ! -f "$DEPS_BASH_PATH" || ! -f "$VALIDATE_JS_PATH" || ! -f "$SCHEMA_VALIDATOR_BASH_PATH" ]]; then
  echo "❌ Error: A required script was not found. Check the paths in the configuration." >&2
  exit 1
fi

# Create a temporary directory for our mock scripts and schemas
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT # Cleanup on exit

# Source the deps.bash script we're testing
# shellcheck source=../deps.bash
source "$DEPS_BASH_PATH"

# Override SCRIPT_REGISTRY_DIR to point to the real project root,
# so the real schema_validator.bash can be found.
SCRIPT_REGISTRY_DIR="$PROJECT_ROOT"

# --- Test Harness (same as before) ---

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
  echo "--- Running Integration Test for deps.bash and validate.js ---"

  # --- Prepare Dependencies for the REAL validate.js ---
  echo "🔹 Ensuring 'ajv' dependency is installed for validate.js..."
  (
    # Go to the directory where the real validate.js lives
    cd "$(dirname "$VALIDATE_JS_PATH")"
    # Silently initialize and install ajv if needed
    if [[ ! -d "node_modules/ajv" ]]; then
        npm init -y >/dev/null 2>&1
        npm install ajv >/dev/null 2>&1
    fi
  )
  echo "🔹 Setup complete."
  # -----------------------------------------------------------------

  # --- Test Case 1: Valid Output ---
  local valid_script="$TEST_DIR/valid_output.bash"
  local schema_for_valid="$TEST_DIR/valid_output.output.schema.json"

  # Create a mock script that produces valid JSON
  echo '#!/bin/bash' > "$valid_script"
  echo 'echo ''{"status": "ok", "code": 200}''' >> "$valid_script"
  chmod +x "$valid_script"

  # Create its corresponding schema
  cat > "$schema_for_valid" <<'EOF'
{
  "type": "object", "properties": { "status": { "type": "string" }, "code": { "type": "integer" }}, "required": ["status", "code"]
}
EOF

  register_dep "valid_output_test" "$valid_script"
  assert_success "system correctly validates good output" \
    exec_dep "valid_output_test"

  # --- Test Case 2: Invalid Output ---
  local invalid_script="$TEST_DIR/invalid_output.bash"
  local schema_for_invalid="$TEST_DIR/invalid_output.output.schema.json"

  # Create a mock script that produces invalid JSON (code is a string)
  echo '#!/bin/bash' > "$invalid_script"
  echo 'echo ''{"status": "ok", "code": "200"}''' >> "$invalid_script"
  chmod +x "$invalid_script"

  # Use the same schema definition
  cp "$schema_for_valid" "$schema_for_invalid"

  register_dep "invalid_output_test" "$invalid_script"
  assert_failure "system correctly rejects bad output" \
    exec_dep "invalid_output_test"

  echo
  echo "🎉 All integration tests passed!"
}

# Run the tests
main
