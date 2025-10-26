#!/usr/bin/env bats

source test/test_helper.bash

PIPELINE_SCRIPT="src/tracing/strace/pipeline/collapsed_stack_from_pipeline.bash"

@test "INTEGRATION: collapsed_stack.bash correctly processes fixture directory" {
  run --separate-stderr bash "$PIPELINE_SCRIPT" test/fixtures/tracing/strace_logs
  assert_success
  assert_output "$(cat test/fixtures/tracing/collapsed_stack.txt)"
}

@test "simple" {
  strace_data=$(cat <<EOF
100<parent>     1.0 execve("/usr/bin/parent", ["parent"]) = 0
100<parent>     2.0 clone() = 101<parent>
101<parent>     3.0 execve("/usr/bin/child", ["child"]) = 0
100<parent>     4.0 +++ exited with 0 +++
101<child>      5.0 +++ exited with 0 +++
EOF
)

  # Define the expected output.
  expected_output=$(cat <<EOF
parent <100> 3000000
parent <100>;parent <101> clone() from parent <100> 1000000
parent <100>;child <101> 2000000
EOF
)

  # Run the awk script, piping the test data to it.
  run --separate-stderr bash -c "cat <<< '$strace_data' | bash '$PIPELINE_SCRIPT'"

  # Assert the output is correct.
  assert_success
  assert_output "$expected_output"
}

@test "simple with grandchild" {
  strace_data=$(cat <<EOF
100<parent>     1.0 execve("/usr/bin/parent", ["parent"]) = 0
100<parent>     2.0 clone() = 101<parent>
101<parent>     3.0 execve("/usr/bin/child", ["child"]) = 0
101<child>      4.0 clone() = 102<child>
102<child>      5.0 execve("/usr/bin/grandchild", ["grandchild"]) = 0
102<grandchild> 6.0 +++ exited with 0 +++
100<parent>     7.0 +++ exited with 0 +++
101<child>      7.0 +++ exited with 0 +++
EOF
)

  expected_output=$(cat <<EOF
parent <100> 6000000
parent <100>;parent <101> clone() from parent <100> 1000000
parent <100>;child <101> 4000000
parent <100>;child <101>;child <102> clone() from child <101> 1000000
parent <100>;child <101>;grandchild <102> 1000000
EOF
)

  run --separate-stderr bash -c "cat <<< '$strace_data' | bash '$PIPELINE_SCRIPT'"

  assert_success
  assert_output "$expected_output"
}
