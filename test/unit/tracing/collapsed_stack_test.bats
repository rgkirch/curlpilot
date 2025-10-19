#!/usr/bin/env bats

source test/test_helper.bash

@test "strace collapsed_stack.bash correctly processes a fixture" {
  # Define the path to the fixture directory.
  FIXTURE_DIR="test/fixtures/tracing/strace_logs"

  # Define the expected output. The order is important (sorted alphabetically).
  # Durations are in milliseconds.
  # make (total 5s, child 4s) -> self 1000ms
  # blackbox (total 4s, child 3s) -> self 1000ms
  # scriptA.bash (total 3s, child 1s) -> self 2000ms
  # scriptB.bash (total 1s, no children) -> self 1000ms
  expected_output=$(cat <<'EOF'
make 1000
make;blackbox 1000
make;blackbox;scriptA.bash 2000
make;blackbox;scriptA.bash;scriptB.bash 1000
EOF
)

  # Run the script and capture its output.
  # We sort the output to ensure the comparison is stable.
  run bash src/tracing/strace/collapsed_stack.bash "$FIXTURE_DIR"

  # Assert that the command succeeded and the output matches our expectation.
  assert_success
  assert_output "$expected_output"
}
