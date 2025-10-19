#!/usr/bin/env bats

source test/test_helper.bash

@test "strace collapsed_stack.bash correctly processes a fixture" {
  strace_logs="test/fixtures/tracing/strace_logs"
  run bash src/tracing/strace/collapsed_stack.bash "$strace_logs"
  assert_success
  assert_output "$(cat "test/fixtures/tracing/collapsed_stack.txt")"
}
