#!/usr/bin/env bats
#set -x

bats_require_minimum_version 1.5.0

export PROJECT_ROOT
PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# This setup() function runs before each test.
setup() {
  # Make the helper function available to the `run` command's subshell.
  # The `export -f` command makes a function definition available to child processes.
  export -f run_with_setup
}

# --- Test Runner Helper ---
# This function is designed to be called by `run`. It sets up the necessary
# environment inside the `run` subshell and then executes its arguments.
run_with_setup() {
  # First, load the functions from deps.bash into the subshell
  source "$PROJECT_ROOT/deps.bash"

  # Second, populate the registry just like the original setup() did
  register_dep mock_completion "$PROJECT_ROOT/test/mocks/server/copilot/completion_response.bash"

  # Finally, execute the actual command that was passed as arguments to this function
  "$@"
}

# --- Custom Assertion Helper ---
# This function replicates the logic from the original script's `run_test`.
# It checks an actual JSON output against an "oracle" of expected values,
# where each key in the oracle is a jq filter.
#
# @param1: The actual JSON string produced by the script under test.
# @param2: The oracle JSON string mapping jq filters to expected values.
assert_json_oracle() {
  local actual_json="$1"
  local oracle_json="$2"

  local filters_to_check
  filters_to_check=$(jq -r 'keys[]' <<< "$oracle_json")

  for filter in $filters_to_check; do
    # Get the expected value as a compact JSON literal (e.g., "hello", 50, true).
    local expected_value
    expected_value=$(jq --compact-output --arg f "$filter" '.[$f]' <<< "$oracle_json")

    # Get the actual value by running the filter against the raw output.
    local actual_value
    actual_value=$(jq --compact-output "$filter" <<< "$actual_json")

    if [[ "$expected_value" != "$actual_value" ]]; then
      # The `fail` command is from bats-support and fails the current test
      # with a descriptive message.
      fail "Mismatch on filter: '$filter'\n  - Expected: $expected_value\n  -      Got: $actual_value"
    fi
  done
}

# ===============================================
# ==            TEST CASES                   ==
# ===============================================

@test "Default values are generated correctly" {
  local expected='{
    ".choices[0].message.content": "This is a mock Copilot response.",
    ".usage.prompt_tokens": 10
  }'

  # The `run` command executes the script and captures its output.
  run --separate-stderr run_with_setup exec_dep mock_completion

  assert_success
  assert_json_oracle "$output" "$expected"
}

@test "Custom message is applied correctly" {
  local expected='{
    ".choices[0].message.content": "Hello, world!",
    ".usage.completion_tokens": 50
  }'

  run --separate-stderr run_with_setup exec_dep mock_completion --message-content "Hello, world!"

  assert_success
  assert_json_oracle "$output" "$expected"
}

@test "Completion tokens can be overridden" {
  local expected='{
    ".choices[0].message.content": "test",
    ".usage.completion_tokens": 500
  }'

  run --separate-stderr run_with_setup exec_dep mock_completion --message-content "test" --completion-tokens 500

  assert_success
  assert_json_oracle "$output" "$expected"
}

@test "Prompt tokens can be overridden" {
  local expected='{
    ".usage.prompt_tokens": 123
  }'

  run --separate-stderr run_with_setup exec_dep mock_completion --prompt-tokens 123

  assert_success
  assert_json_oracle "$output" "$expected"
}

@test "Both completion and prompt tokens can be overridden" {
  local expected='{
    ".choices[0].message.content": "Full override",
    ".usage.completion_tokens": 77,
    ".usage.prompt_tokens": 88
  }'

  run --separate-stderr run_with_setup exec_dep mock_completion --message-content "Full override" --completion-tokens 77 --prompt-tokens 88

  assert_success
  assert_json_oracle "$output" "$expected"
}
