#!/usr/bin/env bats

# Load the helper file at the top. Its setup_file() function will run
# automatically by Bats before any tests start.
load 'test_helper'

# This function runs before EACH test in a separate shell process.
setup() {
  # Source your project's dependency script to make its functions available.
  # This provides the `register_dep` command for this test's process.
  source "$PROJECT_ROOT/deps.bash"

  # Now you can safely call your project's functions.
  register_dep "parse_args" "parse_args.bash"
  SCRIPT_TO_TEST="${SCRIPT_REGISTRY[parse_args]}"
}

# --- HELPER FUNCTION ---
run_parser() {
  local spec="$1"
  shift
  local job_ticket
  job_ticket=$(jq -n \
    --argjson spec "$spec" \
    '{"spec": $spec, "args": $ARGS.positional}' \
    --args -- "$@"
  )
  run --separate-stderr bash "$SCRIPT_TO_TEST" "$job_ticket"
}

MAIN_SPEC='{
  "_description": "A test script with various argument types.",
  "model": {"type": "string", "default": "gpt-default"},
  "stream": {"type": "boolean", "default": true},
  "api_key": {"type": "string", "required": true},
  "retries": {"type": "number", "default": 3}
}'

@test "All args provided" {
  expected='{"api_key": "SECRET", "model": "gpt-4", "stream": false, "retries": 5}'
  run_parser "$MAIN_SPEC" --api-key=SECRET --model=gpt-4 --stream=false --retries=5

  assert_success
  assert_json_equal "$output" "$expected"
}

