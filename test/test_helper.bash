bats_require_minimum_version 1.5.0

# Conditionally set PROJECT_ROOT only if it's not already set.
# This allows test files to override it for sandboxing.
: "${PROJECT_ROOT:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"

# Use the stable BATS_LIBS_DIR variable to load libraries.
# This decouples library loading from the sandboxed PROJECT_ROOT.
# Provide a fallback default for running tests directly without the run_tests.bash script.
: "${BATS_LIBS_DIR:="$PROJECT_ROOT/libs"}"
source "$BATS_LIBS_DIR/bats-support/load.bash"
source "$BATS_LIBS_DIR/bats-assert/load.bash"
source "$BATS_LIBS_DIR/bats-file/load.bash"

# --- GLOBAL SETUP & TEARDOWN HOOKS ---

setup() {
  # Source the script-under-test for every test. It will inherit PROJECT_ROOT.
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"

  # If the test file defines a _setup hook, call it.
  if declare -f _setup > /dev/null; then
    _setup
  fi
}

teardown() {
  # If the test file defines a _teardown hook, call it.
  if declare -f _teardown > /dev/null; then
    _teardown
  fi

  # Conditionally dump file contents only during serial runs to avoid race conditions.
  if [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
    echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
    find "$BATS_TEST_TMPDIR" -type f -print0 | sort -z | xargs -0 head &> /dev/fd/3 || true
  fi
}

# --- CUSTOM ASSERTIONS & HELPERS ---

# Asserts that two JSON strings are semantically equal.
assert_json_equal() {
  local actual="$1"
  local expected="$2"
  local sorted_actual
  local sorted_expected

  sorted_expected=$(echo "$expected" | jq -S . 2>/dev/null || true)
  sorted_actual=$(echo "$actual" | jq -S . 2>/dev/null || true)

  if [ "$sorted_actual" != "$sorted_expected" ]; then
    echo "FAIL: JSON output does not match expected." >&3
    echo "Expected:" >&3
    echo "$sorted_expected" >&3
    echo "Got:" >&3
    echo "$sorted_actual" >&3
    return 1
  fi
}

# Enables the curlpilot tracing feature for a test, directing all trace
# files into the unique temporary directory created by Bats for that test.
enable_tracing() {
  # Gracefully fail if not run inside a Bats test.
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    echo "Error: enable_tracing() must be called from within a Bats test case." >&2
    return 1
  fi

  export CURLPILOT_TRACE_DIR="$BATS_TEST_TMPDIR"

  # Log the trace directory to fd 3 for debugging in test output.
  echo "Tracing enabled. Directory: $BATS_TEST_TMPDIR" >&3
}
