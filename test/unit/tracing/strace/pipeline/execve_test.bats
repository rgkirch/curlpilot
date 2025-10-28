#!/usr/bin/env bats

source test/test_helper.bash

_setup() {
  # Set AWKPATH so gawk can find the 'execve.awk' library
  export AWKPATH="src/tracing/strace/pipeline/lib"
}

@test "unit test: execve functions (populates data array)" {
  # 1. --- Define Test Data ---
  raw_args="\"/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/bin/bats\", [\"/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/libs/bats/bin/bats\", \"--timing\", \"-r\", \"test\", \"--no-tempdir-cleanup\", \"--tempdir\", \"/tmp/tmp.xP8irs59KZ/bats-run\"], 0x7fffe22ad1e0 /* 85 vars */"
  pid="11440"
  comm="strace"
  ts="1761391437.673809"
  raw_line="${pid}<${comm}> ${ts} execve(${raw_args}) = 0"

  # 2. --- Define Expected Output ---
  # This is the *actual* output of the functions: the key-value
  # pairs that will *eventually* be turned into JSON.
  # We print them in a stable format for testing.
  expected_output=$(cat <<EOF
key[type] = execve
key[name] = bats --timing -r test --no-tempdir-cleanup --tempdir bats-run
key[start_us] = 1761391437673809
key[pid] = ${pid}
key[strace] = ${raw_line}
EOF
)

  run --separate-stderr gawk \
    -v raw_line="$raw_line" \
    -i src/tracing/strace/pipeline/lib/execve.awk \
    'BEGIN {
        # Test 1: Call the matcher function
        if (match_execve_re(raw_line, fields)) {

            # Test 2: Call the processor function
            # This populates the global `data` array
            process_execve(fields, data, raw_line)

            # Test 3: Print the contents of the `data` array
            # This is the actual result of our unit test.
            for (i = 1; i <= length(data); i += 2) {
                printf "key[%s] = %s\n", data[i], data[i+1]
            }
        } else {
            print "ERROR: match_execve_re() failed to match" > "/dev/stderr"
        }
    }'

  # 4. --- Assertions ---
  echo "STDERR: $stderr"
  assert_success
  assert_output "$expected_output"
}

@test "unit test: execve library ignores non-matching lines" {
  # This test is still valid and important.
  # It proves that the 'match_execve_re' function
  # correctly rejects a line it shouldn't match.

  # 1. --- Define Test Data (a non-execve line) ---
  raw_clone_line="12348<bash> 1700000003.0 clone(CLONE_ARGS) = 12349<bash>"

  # 2. --- Run the Unit Test ---
  # We only load the execve library and check if the matcher
  # *incorrectly* matches the clone line.
  run --separate-stderr gawk \
    -v raw_line="$raw_clone_line" \
    -f src/tracing/strace/pipeline/lib/execve.awk \
    'BEGIN {
        if (match_execve_re(raw_line, fields)) {
            # This should not happen!
            print "ERROR: execve matcher incorrectly matched a clone line!"
        }
    }'

  # 3. --- Assertions ---
  echo "STDERR: $stderr"
  assert_success
  # The correct behavior is to print nothing.
  assert_output ""
}
