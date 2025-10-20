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
  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"

  # Assert the output is correct.
  assert_success
  assert_output "$expected_output"
}

# ---
# REGRESSION TESTS
# ---

@test "UNIT: collapsed_stack.awk aggregates identical stacks [BUGFIX: Aggregation]" {
  # This test ensures that two different PIDs (201, 202) that
  # produce the *same* stack ("parent;cat") have their self-durations
  # summed into a single output line.
  strace_data=$(cat <<EOF
200<parent> 1000.0 execve("/usr/bin/parent", ["parent"])
200<parent> 1001.0 clone() = 201<parent>
200<parent> 1002.0 clone() = 202<parent>
201<parent> 1001.5 execve("/bin/cat", ["cat"])
201<cat> 1003.5 exit_group()
202<parent> 1002.5 execve("/bin/cat", ["cat"])
202<cat> 1005.5 exit_group()
200<parent> 1006.0 exit_group()
EOF
)

  # Expected:
  # parent self: (1006-1000) - (1003.5-1001.5) - (1005.5-1002.5) = 6.0 - 2.0 - 3.0 = 1.0s
  # cat 1 self: 1003.5 - 1001.5 = 2.0s
  # cat 2 self: 1005.5 - 1002.5 = 3.0s
  # Total 'parent;cat' = 2.0 + 3.0 = 5.0s
  expected_output=$(cat <<EOF
parent 1000
parent;cat 5000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output "$expected_output"
}

@test "UNIT: collapsed_stack.awk correctly names 'bash -c' processes [BUGFIX: Naming]" {
  # This test ensures that a process executing 'bash -c "..."'
  # is correctly named "bash" and not "-c".
  strace_data=$(cat <<EOF
300<parent> 1000.0 execve("/usr/bin/parent", ["parent"])
300<parent> 1001.0 clone() = 301<parent>
301<parent> 1001.5 execve("/bin/bash", ["bash", "-c", "date"])
301<bash> 1002.0 clone() = 302<bash>
302<bash> 1002.5 execve("/bin/date", ["date"])
302<date> 1003.5 exit_group()
301<bash> 1004.0 exit_group()
300<parent> 1005.0 exit_group()
EOF
)

  # Expected:
  # parent self: (1005-1000) - (1004-1001.5) = 5.0 - 2.5 = 2.5s
  # bash self: (1004-1001.5) - (1003.5-1002.5) = 2.5 - 1.0 = 1.5s
  # date self: 1003.5 - 1002.5 = 1.0s
  expected_output=$(cat <<EOF
parent 2500
parent;bash 1500
parent;bash;date 1000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output "$expected_output"
}

@test "UNIT: collapsed_stack.awk filters transient shell helpers [BUGFIX: Filtering]" {
  # This test ensures that transient helper shells (like BATS's
  # internal runners) that fork but never call 'execve' are
  # filtered from the final stack.
  strace_data=$(cat <<EOF
400<bats> 1000.0 execve("/usr/bin/bats", ["bats"])
400<bats> 1001.0 clone() = 401<bash>
401<bash> 1002.0 clone() = 402<bash>
402<bash> 1003.0 execve("/bin/bash", ["bash", "-c", "echo"])
402<bash> 1004.0 clone() = 403<echo>
403<echo> 1005.0 execve("/bin/echo", ["echo"])
403<echo> 1006.0 exit_group()
402<bash> 1007.0 exit_group()
401<bash> 1008.0 exit_group()
400<bats> 1009.0 exit_group()
EOF
)

  # Expected:
  # PID 401 (transient shell) should be skipped.
  # bats (400) self: (1009-1000) - (1008-1001) = 9.0 - 7.0 = 2.0s
  # bash (402) self: (1007-1003) - (1006-1005) = 4.0 - 1.0 = 3.0s
  # echo (403) self: 1006.0 - 1005.0 = 1.0s
  #
  # The stack for PID 402 will be 'bats;bash' (skipping 401).
  # The stack for PID 403 will be 'bats;bash;echo' (skipping 401).
  expected_output=$(cat <<EOF
bats 2000
bats;bash 3000
bats;bash;echo 1000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output "$expected_output"
}

@test "UNIT: collapsed_stack.awk correctly parses 'bats-exec-test' [BUGFIX: Test Naming]" {
  # This test ensures that 'bats-exec-test' is correctly parsed,
  # and its command name is replaced with "test_file.bats;test_name".
  strace_data=$(cat <<EOF
500<bats> 1000.0 execve("/usr/bin/bats", ["bats"])
500<bats> 1001.0 clone() = 501<bats>
501<bats> 1002.0 execve("/usr/bin/bats-exec-suite", ["bats-exec-suite"])
501<bats-exec-suite> 1003.0 clone() = 502<bats-exec-suite>
502<bats-exec-suite> 1004.0 execve("/usr/bin/bats-exec-file", ["bats-exec-file"])
502<bats-exec-file> 1005.0 clone() = 503<bats-exec-file>
503<bats-exec-file> 1006.0 execve("/usr/bin/bats-exec-test", ["/usr/bin/bats-exec-test", "--dummy", "-T", "-x", "/full/path/to/my_test.bats", "test_name_mangled", "14", "1", "1"])
503<my_test.bats> 1007.0 clone() = 504<my_test.bats>
504<my_test.bats> 1008.0 execve("/bin/mkdir", ["mkdir", "-p", "foo"])
504<mkdir> 1009.0 exit_group()
503<my_test.bats> 1010.0 exit_group()
502<bats-exec-file> 1011.0 exit_group()
501<bats-exec-suite> 1012.0 exit_group()
500<bats> 1013.0 exit_group()
EOF
)

  # Expected:
  # bats self: (1013-1000) - (1012-1002) = 13 - 10 = 3.0s
  # bats-exec-suite self: (1012-1002) - (1011-1004) = 10 - 7 = 3.0s
  # bats-exec-file self: (1011-1004) - (1010-1006) = 7 - 4 = 3.0s
  # my_test.bats;test_name_mangled self: (1010-1006) - (1009-1008) = 4 - 1 = 3.0s
  # mkdir self: 1009 - 1008 = 1.0s
  expected_output=$(cat <<EOF
bats 3000
bats;bats-exec-suite 3000
bats;bats-exec-suite;bats-exec-file 3000
bats;bats-exec-suite;bats-exec-file;my_test.bats;test_name_mangled 3000
bats;bats-exec-suite;bats-exec-file;my_test.bats;test_name_mangled;mkdir 1000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output "$expected_output"
}

@test "UNIT: collapsed_stack.awk shell heuristic fallback still works [REGRESSION]" {
  # This test ensures that changing the 'if' to 'else if'
  # for the shell heuristic didn't break it.
  strace_data=$(cat <<EOF
600<parent> 1000.0 execve("/usr/bin/parent", ["parent"])
600<parent> 1001.0 clone() = 601<parent>
601<parent> 1002.0 execve("/bin/bash", ["bash", "my_script.sh", "arg1"])
601<my_script.sh> 1004.0 exit_group()
600<parent> 1005.0 exit_group()
EOF
)

  # Expected:
  # parent self: (1005-1000) - (1004-1002) = 5 - 2 = 3.0s
  # my_script.sh self: 1004 - 1002 = 2.0s
  expected_output=$(cat <<EOF
parent 3000
parent;my_script.sh 2000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output "$expected_output"
}

@test "UNIT: collapsed_stack.awk correctly parses 'bats-exec-test' within BATS hierarchy [BUGFIX: Test Naming Realistic]" {
  # This test uses a more realistic BATS process hierarchy to ensure
  # the bats-exec-test heuristic works in context, not just in isolation.
  strace_data=$(cat <<EOF
700<bats> 1000.0 execve("/usr/bin/bats", ["bats", "test.bats"])
700<bats> 1001.0 clone() = 701<bats>
701<bats> 1002.0 execve("/usr/bin/bats-exec-suite", ["bats-exec-suite", "test.bats"])
701<bats-exec-suite> 1003.0 clone() = 702<bats-exec-suite>
702<bats-exec-suite> 1004.0 execve("/usr/bin/bats-exec-file", ["bats-exec-file", "test.bats"])
702<bats-exec-file> 1005.0 clone() = 703<bats-exec-file>
703<bats-exec-file> 1006.0 execve("/usr/bin/bats-exec-test", ["/usr/bin/bats-exec-test", "-x", "/path/to/my_test_file.bats", "test_actual_name", "1", "1", "1"])
# Note: The awk script uses the basename 'my_test_file.bats' and 'test_actual_name'
703<my_test_file.bats;test_actual_name> 1007.0 clone() = 704<my_test_file.bats;test_actual_name>
704<my_test_file.bats;test_actual_name> 1008.0 execve("/bin/mkdir", ["mkdir", "foo"])
704<mkdir> 1009.0 exit_group()
703<my_test_file.bats;test_actual_name> 1010.0 exit_group()
702<bats-exec-file> 1011.0 exit_group()
701<bats-exec-suite> 1012.0 exit_group()
700<bats> 1013.0 exit_group()
EOF
)

  # Expected Durations:
  # bats (700): (1013-1000) - (1012-1002) = 13 - 10 = 3s
  # bats-exec-suite (701): (1012-1002) - (1011-1004) = 10 - 7 = 3s
  # bats-exec-file (702): (1011-1004) - (1010-1006) = 7 - 4 = 3s
  # my_test_file.bats;test_actual_name (703): (1010-1006) - (1009-1008) = 4 - 1 = 3s
  # mkdir (704): 1009 - 1008 = 1s
  expected_output=$(cat <<EOF
bats 3000
bats;bats-exec-suite 3000
bats;bats-exec-suite;bats-exec-file 3000
bats;bats-exec-suite;bats-exec-file;my_test_file.bats;test_actual_name 3000
bats;bats-exec-suite;bats-exec-file;my_test_file.bats;test_actual_name;mkdir 1000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  # Use assert_output -- instead of assert_output "$expected_output"
  # This makes multiline diffs much easier to read in case of failure.
  assert_output -- "$expected_output"
}
