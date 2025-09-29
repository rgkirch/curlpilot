# test/test_helper.bash

bats_require_minimum_version 1.5.0

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/test/bats/bats-support/load.bash"
source "$PROJECT_ROOT/test/bats/bats-assert/load.bash"
source "$PROJECT_ROOT/test/bats/bats-file/load.bash"



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
