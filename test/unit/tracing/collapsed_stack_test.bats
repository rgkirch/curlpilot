#!/usr/bin/env bats

source test/test_helper.bash

@test "INTEGRATION: collapsed_stack.bash correctly processes fixture directory" {
  run bash src/tracing/strace/collapsed_stack.bash test/fixtures/tracing/strace_logs
  assert_success
  assert_output "$(cat test/fixtures/tracing/collapsed_stack.txt)"
}

@test "UNIT: collapsed_stack.awk correctly processes strace stream" {
  # Define multi-line strace data.
  # PID 100 (parent) runs for 4s total, 1s self.
  # PID 101 (child) runs for 3s total, 1s self.
  # PID 102 (grandchild) runs for 2s total, 2s self.
  strace_data=$(cat <<EOF
100<parent> 1000.0 execve("/usr/bin/parent", ["parent"])
100<parent> 1000.5 clone() = 101<parent>
100<parent> 1004.0 exit_group()
101<parent> 1001.0 execve("/usr/bin/child", ["child"])
101<child> 1001.5 clone() = 102<child>
101<child> 1004.0 exit_group()
102<child> 1002.0 execve("/bin/bash", ["bash", "grandchild.sh"])
102<grandchild.sh> 1004.0 exit_group()
EOF
)

  # Define the expected output.
  expected_output=$(cat <<EOF
parent 1000
parent;child 1000
parent;child;grandchild.sh 2000
EOF
)

  # Run the awk script, piping the test data to it.
  # Note: The 'gawk' binary must be called correctly as per your environment.
  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"

  # Assert the output is correct.
  assert_success
  assert_output "$expected_output"
}
