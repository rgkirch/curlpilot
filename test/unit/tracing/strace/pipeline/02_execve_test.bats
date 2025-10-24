#!/usr/bin/env bats

source test/test_helper.bash

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
#  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$strace_data"
#  assert_success
#  assert_output --partial "$expected_output"
#}

_setup() {
  # Define the Unit Separator (ASCII 31)
  # Using printf is more portable than $'\037' in some shells.
  US=$(printf '\037')
}

@test "Test 1: bats-preprocess (User's specific case)" {
  # This mocks the raw strace line and the parsed args string from 01_parse.awk
  args_1='"/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/libexec/bats-core/bats-preprocess", ["/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/libexec/bats-core/bats-preprocess", "/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test/generate_help_text_test.bats"], 0x561920747ed0 /* 112 vars */'
  raw_line_1="13606<bash> 1761220544.057849 execve(${args_1}) = 0"

  # Format: tag<US>pid<US>comm<US>timestamp<US>args<US>result<US>raw_line
  input_data="execve${US}13606${US}bash${US}1761220544.057849${US}${args_1}${US}0${US}${raw_line_1}"

  # Expected format: json<US>name<US>span_name<US>start_us<US>us_val<US>pid<US>pid_val ...
  # The script should identify "generate_help_text_test.bats" as the primary action.
  expected_output=$(printf "json%sname%sbats-preprocess: generate_help_text_test.bats <13606>%sstart_us%s1761220544057849%spid%s13606" "$US" "$US" "$US" "$US" "$US")

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output --partial "$expected_output"
}

@test "Test 2: Command with flags and path (ls -l -a /tmp)" {
  raw_line_2='12345<bash> 1700000000.123456 execve("/usr/bin/ls", ["ls", "-l", "-a", "/tmp"], 0xABC) = 0'
  args_2='"/usr/bin/ls", ["ls", "-l", "-a", "/tmp"], 0xABC'

  input_data="execve${US}12345${US}bash${US}1700000000.123456${US}${args_2}${US}0${US}${raw_line_2}"

  # The script should identify "/tmp" as primary action and "-l", "-a" as flags.
  # It should also take the basename of "/tmp".
  expected_output=$(printf "json%sname%sls: tmp [ -l, -a ] <12345>%sstart_us%s1700000000123456%spid%s12345" "$US" "$US" "$US" "$US" "$US")

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output --partial "$expected_output"
}

@test "Test 3: Command with no args (pwd)" {
  raw_line_3='12346<bash> 1700000001.000000 execve("/usr/bin/pwd", ["pwd"], 0xABC) = 0'
  args_3='"/usr/bin/pwd", ["pwd"], 0xABC'

  input_data="execve${US}12346${US}bash${US}1700000001.000000${US}${args_3}${US}0${US}${raw_line_3}"

  # No primary action, no flags.
  expected_output=$(printf "json%sname%spwd <12346>%sstart_us%s1700000001000000%spid%s12346" "$US" "$US" "$US" "$US" "$US")

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output --partial "$expected_output"
}

@test "Test 4: Command with only flags (ls -l)" {
  raw_line_4='12347<bash> 1700000002.500000 execve("/usr/bin/ls", ["ls", "-l"], 0xABC) = 0'
  args_4='"/usr/bin/ls", ["ls", "-l"], 0xABC'

  input_data="execve${US}12347${US}bash${US}1700000002.500000${US}${args_4}${US}0${US}${raw_line_4}"

  # No primary action, only flags.
  expected_output=$(printf "json%sname%sls [ -l ] <12347>%sstart_us%s1700000002500000%spid%s12347" "$US" "$US" "$US" "$US" "$US")

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output --partial "$expected_output"
}

@test "Test 5: Command with complex args (grep -e \"foo \\\"bar\\\" baz\")" {
  # Note the escaped quotes for the shell here-doc
  raw_line_5='12349<bash> 1700000004.000000 execve("/usr/bin/grep", ["grep", "-e", "foo \"bar\" baz", "file.txt"], 0xABC) = 0'
  args_5='"/usr/bin/grep", ["grep", "-e", "foo \"bar\" baz", "file.txt"], 0xABC'

  input_data="execve${US}12349${US}bash${US}1700000004.000000${US}${args_5}${US}0${US}${raw_line_5}"

  # Per your script's logic, the *first* non-flag arg is the primary action.
  # So, "foo \"bar\" baz" becomes the primary action, not "file.txt".
  expected_output=$(printf "json%sname%sgrep: foo \"bar\" baz [ -e ] <12349>%sstart_us%s1700000004000000%spid%s12349" "$US" "$US" "$US" "$US" "$US")

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output --partial "$expected_output"
}

@test "Test 6: Non-execve line (passthrough)" {
  # This mocks a "clone" line from 01_parse.awk
  # Format: tag<US>pid<US>comm<US>timestamp<US>args<US>new_pid<US>new_comm<US>raw_line
  input_data="clone${US}12348${US}bash${US}1700000003.0${US}CLONE_ARGS${US}12349${US}bash${US}RAW_CLONE_LINE"

  # Expected output is the identical, unmodified input line
  expected_output="$input_data"

  run gawk -f src/tracing/strace/pipeline/02_execve.awk <<< "$input_data"
  assert_success
  assert_output "$expected_output"
}
