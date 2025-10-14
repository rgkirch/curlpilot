bats_require_minimum_version 1.5.0

# --- GLOBAL SETUP & TEARDOWN HOOKS ---

# This global setup runs before EACH test in a file.
setup() {
  # If the specific test file being run has its own setup function, call it.
  # This allows for test-file-specific setup logic.
  if declare -f _setup > /dev/null; then
    _setup
  fi
}

teardown() {
  if declare -f _teardown > /dev/null; then
    _teardown
  fi

  # If tracing is enabled and the test failed, dump all files created during the test for debugging.
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]] && [[ -n "${BATS_ERROR_STATUS:-}" && "${BATS_ERROR_STATUS}" -ne 0 ]] && [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
    echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
    find "$BATS_TEST_TMPDIR" -type f -print0 | sort -z | xargs -0 head &> /dev/fd/3 || true
  fi
}


# --- LOAD BATS LIBRARIES ---

# First, calculate the absolute path to the project root relative to THIS script's location.
# This is the most reliable way to find the BATS helper libraries.
_BATS_LIBS_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the BATS helper libraries using this reliable, internal path.
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-support/load.bash"
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-assert/load.bash"
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-file/load.bash"

# Now, set a default for the PROJECT_ROOT that tests will use.
# This allows an external script to override the value for sandboxing or other purposes,
# without breaking the library loading above.
: "${PROJECT_ROOT:=$_BATS_LIBS_PROJECT_ROOT}"
export PROJECT_ROOT


# --- CUSTOM ASSERTIONS & HELPERS ---

# Asserts that two JSON strings are semantically equal by sorting their keys.
assert_json_equal() {
  local actual="$1"
  local expected="$2"
  local sorted_actual
  local sorted_expected

  # The `|| true` prevents the command from failing the script if jq encounters
  # invalid JSON, allowing the final comparison to correctly report the failure.
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
