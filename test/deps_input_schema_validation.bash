#!/bin/bash
#
# An integration test that verifies deps.bash correctly applies
# INPUT schema validation to a script's stdin.
#
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
  echo "--- Running Input Schema Validation Tests ---"

  if [[ ! -f "$VALIDATE_JS_PATH" ]]; then
    echo "❌ Error: validate.js not found at '$VALIDATE_JS_PATH'" >&2
    exit 1
  fi

  # --- Prepare Dependencies for the REAL validate.js ---
  echo "🔹 Ensuring 'ajv' dependency is installed..."
  (
    cd "$(dirname "$VALIDATE_JS_PATH")"
    if [[ ! -d "node_modules/ajv" ]]; then
        npm init -y >/dev/null 2>&1
        npm install ajv >/dev/null 2>&1
    fi
  )
  echo "🔹 Setup complete."

  # --- Create a single mock script and its input schema ---
  local mock_script_path="$TEST_DIR/input_processor.bash"
  local mock_schema_path="$TEST_DIR/input_processor.input.schema.json"

  # This script reads JSON from stdin and adds a "processed" field.
  cat > "$mock_script_path" <<'EOF'
#!/bin/bash
# A simple script that requires jq to be installed.
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. This mock script requires it." >&2
  exit 1
fi
jq '.processed = true'
EOF
  chmod +x "$mock_script_path"

  # This schema requires the input JSON to have a "user_id" integer.
  cat > "$mock_schema_path" <<'EOF'
{
  "type": "object",
  "properties": {
    "user_id": { "type": "integer" }
  },
  "required": ["user_id"]
}
EOF
  register_dep "input_test" "$mock_script_path"


  # --- Test Case 1: Valid Input ---
  local valid_json='{"user_id": 123, "data": "stuff"}'
  # The <<< operator provides the string as stdin to the command.
  assert_success "script with valid input passes validation" \
    exec_dep "input_test" <<< "$valid_json"


  # --- Test Case 2: Invalid Input ---
  # This JSON is missing the required "user_id" field.
  local invalid_json='{"data": "stuff"}'
  assert_failure "script with invalid input fails validation" \
    exec_dep "input_test" <<< "$invalid_json"

  echo
  echo "🎉 All input schema validation tests passed!"
}

main
