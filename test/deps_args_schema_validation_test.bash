#!/bin/bash
#
# An integration test that verifies deps.bash correctly applies
# ARGUMENT schema validation to a script's command-line args.
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
  echo "--- Running Argument Schema Validation Tests ---"

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

  # --- Create a single mock script and its args schema ---
  local mock_script_path="$TEST_DIR/args_processor.bash"
  local mock_schema_path="$TEST_DIR/args_processor.args.schema.json"

  # This script simply prints the arguments it received.
  cat > "$mock_script_path" <<'EOF'
#!/bin/bash
echo "Processed command '$1' for file '$2'"
EOF
  chmod +x "$mock_script_path"

  # This schema requires exactly two arguments:
  # 1. The string "upload" or "download".
  # 2. A string that ends with ".zip".
  cat > "$mock_schema_path" <<'EOF'
{
  "type": "array",
  "minItems": 2,
  "maxItems": 2,
  "items": [
    {
      "type": "string",
      "enum": ["upload", "download"]
    },
    {
      "type": "string",
      "pattern": "\\.zip$"
    }
  ]
}
EOF
  register_dep "args_test" "$mock_script_path"


  # --- Test Case 1: Valid Arguments ---
  assert_success "script with valid arguments passes validation" \
    exec_dep "args_test" "upload" "archive.zip" <<< ""


  # --- Test Case 2: Invalid Arguments ---
  # This call is invalid because the first argument is not in the enum.
  assert_failure "script with invalid arguments fails validation" \
    exec_dep "args_test" "delete" "archive.zip" <<< ""

  # This call is invalid because the second argument doesn't match the pattern.
  assert_failure "script with arguments of wrong format fails validation" \
    exec_dep "args_test" "download" "archive.txt" <<< ""

  echo
  echo "🎉 All argument schema validation tests passed!"
}

main
