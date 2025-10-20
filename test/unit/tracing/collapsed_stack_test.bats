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
parent 1000000
parent;child 1000000
parent;child;grandchild.sh 2000000
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
parent 1000000
parent;cat 5000000
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
parent 2500000
parent;bash 1500000
parent;bash;date 1000000
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
bats 2000000
bats;bash 3000000
bats;bash;echo 1000000
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
bats 3000000
bats;bats-exec-suite 3000000
bats;bats-exec-suite;bats-exec-file 3000000
bats;bats-exec-suite;bats-exec-file;my_test.bats;test_name_mangled 3000000
bats;bats-exec-suite;bats-exec-file;my_test.bats;test_name_mangled;mkdir 1000000
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
parent 3000000
parent;my_script.sh 2000000
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
bats 3000000
bats;bats-exec-suite 3000000
bats;bats-exec-suite;bats-exec-file 3000000
bats;bats-exec-suite;bats-exec-file;my_test_file.bats;test_actual_name 3000000
bats;bats-exec-suite;bats-exec-file;my_test_file.bats;test_actual_name;mkdir 1000000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  # Use assert_output -- instead of assert_output "$expected_output"
  # This makes multiline diffs much easier to read in case of failure.
  assert_output -- "$expected_output"
}

@test "UNIT: collapsed_stack.awk correctly parses real strace 'bats-exec-test' line [BUGFIX: Realistic Full Line]" {
  # This test uses a near-exact strace line from your sample...
  #
  # --- FIX: The timestamps have been changed to match the expected durations ---
  # Expected: Parent self-duration = 4000ms, Child self-duration = 1000ms
  #
  # Parent (2734232) start: 1000.0
  # Child (2734233) start:  1001.0
  # Child (2734233) end:    1002.0  (Total duration: 1.0s)
  # Parent (2734232) end:    1005.0  (Total duration: 5.0s)
  #
  # Parent self-time = 5.0s (total) - 1.0s (child) = 4.0s
  # Child self-time = 1.0s
  #
  strace_data=$(cat <<EOF
2734232<bash> 1000.0 execve("/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/libexec/bats-core/bats-exec-test", ["/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/libexec/bats-core/bats-exec-test", "--dummy-flag", "-T", "-x", "/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test/generate_help_text_test.bats", "test_generate-2d5fhelp-2d5ftext_errors_when_description_missing", "15", "2", "1"]) = 0
2734232<bats-exec-test> 1000.5 clone() = 2734233<bats-exec-test>
2734233<bats-exec-test> 1001.0 execve("/bin/echo", ["echo", "hello"]) = 0
2734233<echo> 1002.0 exit_group(0) = ?
2734232<bats-exec-test> 1005.0 exit_group(0) = ?
EOF
)

  expected_output=$(cat <<EOF
generate_help_text_test.bats;test_generate-2d5fhelp-2d5ftext_errors_when_description_missing 4000000
generate_help_text_test.bats;test_generate-2d5fhelp-2d5ftext_errors_when_description_missing;echo 1000000
EOF
)

  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"  # Use --partial if timestamps vary slightly; adjust as needed
}

#@test "foo" {
#  strace_data=$(cat <<EOF
#bar
#EOF
#)
#
#  expected_output=$(cat <<EOF
#baz
#EOF
#)
#
#  run gawk -f src/tracing/strace/collapsed_stack.awk <<< "$strace_data"
#  assert_success
#  assert_output --partial "$expected_output"
#}

AWK_SCRIPT="src/tracing/strace/collapsed_stack.awk"

@test "TEST 1: Basic single process stack" {
  strace_data=$(cat <<EOF
1000<bash> 1760000000.100000 clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f32a2796a10) = 1001<bash>
1001<bash> 1760000000.200000 execve("/usr/bin/sleep", ["sleep", "1"], 0x560e3885cf60 /* 117 vars */) = 0
1000<bash> 1760000000.200100 wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 1001
1001<sleep> 1760000001.200000 exit_group(0) = ?
1001<sleep> 1760000001.200100 +++ exited with 0 +++
EOF
)

  expected_output=$(cat <<EOF
bash;sleep 1000000
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}

# -----------------------------------------------------------------------------

@test "TEST 2: Nested two-level process stack" {
  strace_data=$(cat <<EOF
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve("/bin/sh", ["sh", "-c", "my_script.sh"], ...) = 0
1001<sh>   1760000000.300000 clone(child_stack=NULL, ...) = 1002<sh>
1002<sh>   1760000000.400000 execve("/usr/bin/date", ["date"], ...) = 0
1001<sh>   1760000000.400100 wait4(-1, ...) = 1002
1002<date> 1760000000.500000 +++ exited with 0 +++
1001<sh>   1760000000.600000 exit_group(0) = ?
EOF
)

  # Expected output:
  # The 'date' process ran for 100000 us (0.5 - 0.4)
  # The 'sh' process ran for 400000 us (0.6 - 0.2)
  expected_output_1=$(cat <<EOF
bash;sh;date 99999
EOF
)
  expected_output_2=$(cat <<EOF
bash;sh 299999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output_1"
  assert_output --partial "$expected_output_2"
}

# -----------------------------------------------------------------------------

@test "TEST 3: Command name uses basename of arg[0]" {
  strace_data=$(cat <<EOF
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve("/usr/local/bin/my-custom-tool", ["/usr/local/bin/my-custom-tool", "--foo"], ...) = 0
1001<my-custom-tool> 1760000000.300000 +++ exited with 0 +++
EOF
)

  expected_output=$(cat <<EOF
bash;my-custom-tool 99999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}

# -----------------------------------------------------------------------------

@test "TEST 4: Special case: bats suite runner" {
  strace_data=$(cat <<EOF
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve("/home/me/libs/bats/bin/bats", ["/home/me/libs/bats/bin/bats", "-T", "test/unit/my_awesome_test.bats"], ...) = 0
1001<bats> 1760000002.500000 +++ exited with 0 +++
EOF
)

  # Frame name should be the .bats file, not "bats"
  expected_output=$(cat <<EOF
bash;my_awesome_test.bats 2299999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}

# -----------------------------------------------------------------------------

@test "TEST 5: Special case: bats-exec-test runner (with demangling)" {
  strace_data=$(cat <<EOF
2000<bats> 1760000001.100000 clone(child_stack=NULL, ...) = 2001<bats>
2001<bats> 1760000001.200000 execve("/home/me/libs/bats/libexec/bats-core/bats-exec-test", [".../bats-exec-test", "--dummy", "test/unit/my_awesome_test.bats", "test_AWESOME-3a_TEST-5fNAME-2eFOO", "123"], ...) = 0
2001<bats-exec-test> 1760000001.500000 +++ exited with 0 +++
EOF
)

  # Frame name should be the demangled test name:
  # test_AWESOME-3a_TEST-5fNAME-2eFOO
  # -> AWESOME: TEST_NAME.FOO
  expected_output=$(cat <<EOF
bats;my_awesome_test.bats;test_AWESOME-3a_TEST-5fNAME-2eFOO 299999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}

# -----------------------------------------------------------------------------

@test "TEST 6: Full stack: suite -> test -> command" {
  strace_data=$(cat <<EOF
# 1. Shell clones the bats suite runner
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve(".../bats", [".../bats", "test/my_suite.bats"], ...) = 0

# 2. Suite runner (1001) clones the test runner
1001<bats> 1760000001.000000 clone(child_stack=NULL, ...) = 1002<bats>
1002<bats> 1760000001.100000 execve(".../bats-exec-test", [".../bats-exec-test", "test/my_suite.bats", "test_MY-3a_TEST-5fCASE"], ...) = 0

# 3. Test runner (1002) clones the actual command
1002<bats-exec-test> 1760000002.000000 clone(child_stack=NULL, ...) = 1003<bats-exec-test>
1003<bats-exec-test> 1760000002.100000 execve("/usr/bin/gawk", ["gawk", "-f", "my_script.awk"], ...) = 0

# 4. Processes exit in reverse order
1003<gawk> 1760000002.500000 +++ exited with 0 +++
1002<bats-exec-test> 1760000002.600000 wait4(1003, ...) = 1003
1002<bats-exec-test> 1760000003.000000 +++ exited with 0 +++
1001<bats> 1760000003.100000 wait4(1002, ...) = 1002
1001<bats> 1760000004.000000 +++ exited with 0 +++
1000<bash> 1760000004.100000 wait4(1001, ...) = 1001
EOF
)

  # Expected gawk stack: bash;my_suite.bats;MY: TEST_CASE;gawk
  # Duration: 2.5 - 2.1 = 0.4s = 400000 us
  expected_stack_1="bash;bats;my_suite.bats;test_MY-3a_TEST-5fCASE;gawk 400000"

  # Expected test stack: bash;my_suite.bats;MY: TEST_CASE
  # Duration: 3.0 - 1.1 = 1.9s = 1900000 us
  expected_stack_2="bash;bats;my_suite.bats;test_MY-3a_TEST-5fCASE 1500000"

  # Expected suite stack: bash;my_suite.bats
  # Duration: 4.0 - 0.2 = 3.8s = 3800000 us
  expected_stack_3="bash;bats 1899999"


  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_stack_1"
  assert_output --partial "$expected_stack_2"
  assert_output --partial "$expected_stack_3"
}

# -----------------------------------------------------------------------------

@test "TEST 7: Ignores processes without an execve (pre-existing)" {
  strace_data=$(cat <<EOF
# This process has no execve, it should be ignored
9000<existing-proc> 1760000000.050000 +++ exited with 0 +++

# This is a valid, complete process
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve("/usr/bin/true", ["true"], ...) = 0
1001<true> 1760000000.250000 +++ exited with 0 +++
EOF
)

  expected_output=$(cat <<EOF
bash;true 49999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
  refute_output --partial "existing-proc"
}

# -----------------------------------------------------------------------------

@test "TEST 8: Handles 'exit_group' as well as '+++ exited with +++'" {
  strace_data=$(cat <<EOF
# From user's provided logs. 'exit_group' appears first.
2363757<bash> 1760974192.628742 clone(child_stack=NULL, ...) = 2363758<bash>
2363758<bash> 1760974192.629393 execve("/usr/bin/cat", ["cat", "/tmp/file"], ...) = 0
2363757<bash> 1760974192.629042 wait4(-1, ...) = 2363758
2363758<cat> 1760974192.630641 exit_group(1) = ?
2363758<cat> 1760974192.630722 +++ exited with 1 +++
EOF
)
  # Duration should be based on the *first* exit event (exit_group)
  # 1760974192.630641 - 1760974192.629393 = 0.001248s = 1248 us
  expected_output=$(cat <<EOF
bash;cat 1247
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}

# -----------------------------------------------------------------------------

@test "TEST 9: Handles processes with no args (e.g., kernel threads)" {
  strace_data=$(cat <<EOF
1000<bash> 1760000000.100000 clone(child_stack=NULL, ...) = 1001<bash>
1001<bash> 1760000000.200000 execve("/usr/bin/awk", ["awk"], ...) = 0
1001<awk> 1760000000.300000 +++ exited with 0 +++
EOF
)
  # Should not fail, just use the command name
  expected_output=$(cat <<EOF
bash;awk 99999
EOF
)

  run gawk -f "$AWK_SCRIPT" <<< "$strace_data"
  assert_success
  assert_output --partial "$expected_output"
}
