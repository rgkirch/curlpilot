# test/test_helper.bash

bats_require_minimum_version 1.5.0

export PROJECT_ROOT
PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

source "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
source "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"



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
