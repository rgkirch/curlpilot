set -euo pipefail

# This script tests the functionality of schema_validator.sh.
# It must be run from the project's root directory.

echo "🧪 Running tests for schema_validator.sh..."

# --- Prerequisite Check ---
# Ensure ajv-cli is installed before running the tests.
if ! command -v ajv &> /dev/null; then
  echo "❌ Prerequisite 'ajv-cli' not found. Please run: npm install -g ajv-cli" >&2
  exit 1
fi

# --- Test Setup ---
# Create a temporary directory for our test files.
TEST_DIR=$(mktemp -d)
# Ensure the temporary directory is removed when the script exits.
trap 'rm -rf "$TEST_DIR"' EXIT

# Define paths for our test schema and data.
SCHEMA_FILE="$TEST_DIR/test.schema.json"
VALID_DATA='{"name": "Alice", "age": 30}'
INVALID_DATA='{"name": "Bob", "age": "thirty"}' # age should be a number

# Create the schema file.
cat > "$SCHEMA_FILE" << EOF
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "number" }
  },
  "required": ["name", "age"]
}
EOF

# --- Test Runner ---
failures=0
# Usage: run_test <description> <expected_exit_code> <command> [args...]
# The command inherits its stdin from this function, allowing for piping.
run_test() {
  local description="$1"
  local expected_exit_code="$2"
  shift 2 # The rest of the arguments are the command to execute.

  printf "  - %s... " "$description"

  # Run the command, capturing its output (stdout & stderr) and exit code.
  set +e
  output=$("$@" 2>&1)
  local exit_code=$?
  set -e

  if [[ $exit_code -ne $expected_exit_code ]]; then
    printf "FAIL ❌\n"
    echo "    Expected exit code $expected_exit_code, but got $exit_code."
    echo "    Output:"
    echo "$output" | sed 's/^/    | /'
    failures=$((failures + 1))
  else
    printf "PASS ✅\n"
  fi
}

# --- Execute Tests ---
# Pipe data *into* the run_test function, which passes it to the command.
echo "$VALID_DATA" | run_test "Success: Valid data should pass silently" 0 \
  ./schema_validator.sh "$SCHEMA_FILE"

echo "$INVALID_DATA" | run_test "Failure: Invalid data should fail with an error" 1 \
  ./schema_validator.sh "$SCHEMA_FILE"

# For commands that don't need stdin, just call run_test directly.
run_test "Failure: A non-existent schema file should cause an error" 1 \
  ./schema_validator.sh '/no/such/file.json'

run_test "Failure: Missing schema file argument should show usage" 1 \
  ./schema_validator.sh


# --- Final Report ---
if [[ $failures -gt 0 ]]; then
  echo "❌ $failures test(s) failed."
  exit 1
else
  echo "✅ All schema validator tests passed."
  exit 0
fi
