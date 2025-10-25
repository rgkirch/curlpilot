#!/usr/bin/env bats

source test/test_helper.bash

@test "missing touch" {
  data=$(cat <<EOF
{"name": "bash <12107> (cloned from bats-exec-file)", "start_us": "1761391444642.829", "pid": "12107", "parent_pid": "12101", "strace": "12101<bats-exec-file> 1761391444.642829 clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f5a02205a10) = 12107<bash>"}
{"name": "touch <12107>", "start_us": "1761391444643.058", "pid": "12107", "strace": "12107<bash> 1761391444.643058 execve(\"/usr/bin/touch\", [\"touch\", \"/tmp/tmp.xP8irs59KZ/bats-run/file/1-deps_test.bats.out\"], 0x55922a584650 /* 113 vars */) = 0"}
{"type": "exited", "pid": "12107", "end_us": "1761391444643.823", "exit_code": "0", "strace": "12107<touch> 1761391444.643823 +++ exited with 0 +++"}
EOF
)
  expected_output=$(cat <<EOF
[
  {
    "name": "bash <12107> (cloned from bats-exec-file)",
    "start_us": "1761391444642.829",
    "pid": "12107",
    "parent_pid": "12101",
    "strace": "12101<bats-exec-file> 1761391444.642829 clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f5a02205a10) = 12107<bash>",
    "end_us": "1761391444643.058"
  },
  {
    "name": "touch <12107>",
    "start_us": "1761391444643.058",
    "pid": "12107",
    "strace": "12107<touch> 1761391444.643823 +++ exited with 0 +++",
    "type": "exited",
    "end_us": "1761391444643.823",
    "exit_code": "0"
  }
]
EOF
)

  run jq -s -f src/tracing/strace/pipeline/stitch_spans.jq <<< "$data"
  assert_success
  # Use exact match for the beautified JSON output
  assert_output "$expected_output"
}
