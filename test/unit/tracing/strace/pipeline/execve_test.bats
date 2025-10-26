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
#  run gawk -f src/tracing/strace/pipeline/???_execve.awk <<< "$strace_data"
#  assert_success
#  assert_output --partial "$expected_output"
#}

_setup() {
  # Define the Unit Separator (ASCII 31)
  # Using printf is more portable than $'\037' in some shells.
  US=$(printf '\037')
}

@test "test execve" {
  raw_args="\"/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/bin/bats\", [\"/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/bin/bats\", \"--timing\", \"-r\", \"test\", \"--no-tempdir-cleanup\", \"--tempdir\", \"/tmp/tmp.xP8irs59KZ/bats-run\"], 0x7fffe22ad1e0 /* 85 vars */"
  raw_line="11440<strace> 1761391437.673809 execve(${raw_args}) = 0"
  input_data="execve${US}11440${US}strace${US}1761220544.057849${US}${raw_args}${US}0${US}${raw_line}"
  expected_output="json${US}type${US}execve${US}name${US}bats --timing -r test --no-tempdir-cleanup --tempdir bats-run${US}start_us${US}1761220544057849${US}pid${US}11440"

  run --separate-stderr gawk -f src/tracing/strace/pipeline/???_execve.awk <<< "$input_data"
  echo "STDERR: $stderr"
  assert_success
  assert_output --partial "${expected_output}${US}strace${US}${raw_line}${US}debug_text${US}"
}

@test "Test 6: Non-execve line (passthrough)" {
  # This mocks a "clone" line from 01_parse.awk
  # Format: tag<US>pid<US>comm<US>timestamp<US>args<US>new_pid<US>new_comm<US>raw_line
  input_data="clone${US}12348${US}bash${US}1700000003.0${US}CLONE_ARGS${US}12349${US}bash${US}RAW_CLONE_LINE"

  # Expected output is the identical, unmodified input line
  expected_output="$input_data"

  run gawk -f src/tracing/strace/pipeline/???_execve.awk <<< "$input_data"
  assert_success
  assert_output "$expected_output"
}
