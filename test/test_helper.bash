# test/test_helper.bash

bats_require_minimum_version 1.5.0

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/libs/bats-support/load.bash"
source "$PROJECT_ROOT/libs/bats-assert/load.bash"
source "$PROJECT_ROOT/libs/bats-file/load.bash"

# --- CUSTOM ASSERTION ---
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

# --- TRACING HELPER ---
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
  echo "Tracing enabled. Directory: $CURLPILOT_TRACE_DIR" >&3
}

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/test_helper.bash"
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  _setup
}

teardown() {
  echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
  find "$BATS_TEST_TMPDIR" -type f -print0 | sort -z | xargs -0 head &> /dev/fd/3 || true
}
