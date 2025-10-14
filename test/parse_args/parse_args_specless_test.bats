#!/usr/bin/env bats
#test/parse_args/parse_args_specless_test.bats

source test/test_helper.bash
source src/logging.bash

parse_args() (
  source deps.bash
  set -euo pipefail

  _exec_dep "$PROJECT_ROOT/src/parse_args/parse_args_specless.bash" "parse_args_specless" "$@"
)


_assert_key_string() {
  local json="$1" key="$2" expected="$3"
  run jq -r --arg k "$key" '.[$k]' <<<"$json"
  assert_success
  assert_output "$expected"
}

_assert_key_true() {
  local json="$1" key="$2"
  log_trace "key $key json $json"
  run jq -r --arg k "$key" '.[$k]' <<<"$json"
  assert_success
  log_trace "output from _assert_key_true $output"
  assert_output 'true'
}

@test "long boolean flags" {
  run parse_args --foo --bar
  assert_success
  parsed="$output"
  _assert_key_true "$parsed" foo
  _assert_key_true "$parsed" bar
}

@test "long separated value" {
  run parse_args --name value
  assert_success
  _assert_key_string "$output" name value
}

@test "dash-leading value via equals" {
  run parse_args --pattern=--abc
  assert_success
  _assert_key_string "$output" pattern --abc
}

@test "short cluster letters" {
  run parse_args -abc
  assert_success
  log_trace "output $output"
  parsed="$output"
  _assert_key_true "$parsed" a
  _assert_key_true "$parsed" b
  _assert_key_true "$parsed" c
}

@test "error on digit in short cluster" {
  run parse_args -ab1
  assert_failure
  [[ "$output" == *"invalid short option cluster"* ]] || fail "Expected invalid cluster error, got: $output"
}

@test "error on duplicate key" {
  run parse_args --foo --foo
  assert_failure
  [[ "$output" == *"duplicate key"* ]] || fail "Expected duplicate key error, got: $output"
}

@test "normalization of dashed long key" {
  run parse_args --foo-bar
  assert_success
  _assert_key_true "$output" foo_bar
}

@test "empty value with equals" {
  run parse_args --empty=
  assert_success
  _assert_key_string "$output" empty ""
}

@test "stray value error" {
  run parse_args value_only
  assert_failure
  [[ "$output" == *"stray value"* ]] || fail "Expected stray value error, got: $output"
}

@test "boolean flag before short cluster treated separately" {
  run parse_args --flag -xy
  assert_success
  parsed="$output"
  _assert_key_true "$parsed" flag
  _assert_key_true "$parsed" x
  _assert_key_true "$parsed" y
}

@test "negative number requires equals form" {
  run parse_args --num=-10
  assert_success
  _assert_key_string "$output" num -10
  run parse_args --num -10
  assert_failure
  [[ "$output" == *"invalid short option cluster"* || "$output" == *"value for --num starts with"* ]] || fail "Expected error for separated negative number, got: $output"
}

# @test "long separated value with newlines" {
#   multiline_val='"[\n  \"/tmp/bats-run-52tUAo/test/1/r1.http\",\n  \"/tmp/bats-run-52tUAo/test/1/r2.http\"\n]"'
#   log_debug '"[\n  \"/tmp/bats-run-52tUAo/test/1/r1.http\",\n  \"/tmp/bats-run-52tUAo/test/1/r2.http\"\n]"'
#   run parse_args "\"--responses\"" "$multiline_val" "\"--request_dir\"" "/tmp/bats-run-q9sMj1/test/1/requests" "\"--stdout_log\"" "\"3\"" "--stderr_log" "\"3\"" "--port" 64799
#   assert_success
#   _assert_key_string "$output" responses "$multiline_val"
# }


@test "quotes don't make values different" {
  run parse_args --foo "bar"
  assert_success
  parsed="$output"
  _assert_key_string "$parsed" foo bar
}

@test "value is a simple JSON array string" {
  local json_val='["bar", "baz"]'
  run parse_args --foo "$json_val"
  assert_success
  _assert_key_string "$output" foo "$json_val"
}

@test "value is a JSON object string with newlines" {
  # Create a multi-line JSON string as the value
  local json_val
  json_val=$(jq . <<<'{"key1": "value1", "key2": ["a", "b"]}')

  run parse_args --data "$json_val"
  assert_success
  _assert_key_string "$output" data "$json_val"
}


@test "uppercase long key normalization" {
  run parse_args --FooBar
  assert_success
  _assert_key_true "$output" foobar
}

@test "invalid long key characters" {
  run parse_args --foo!
  assert_failure
  [[ "$output" == *"invalid key characters"* ]] || fail "Expected invalid key characters error, got: $output"
}

@test "standalone double dash begins positional collection" {
  run parse_args -- a b
  assert_success
  parsed="$output"
  run jq -r '._positional | length' <<<"$parsed"; assert_output "2"
  run jq -r '._positional[0]' <<<"$parsed"; assert_output "a"
  run jq -r '._positional[1]' <<<"$parsed"; assert_output "b"
}

@test "lone dash error" {
  run parse_args -
  assert_failure
  [[ "$output" == *"lone '-' is invalid"* ]] || fail "Expected lone dash error, got: $output"
}

@test "duplicate after normalization" {
  run parse_args --foo-bar --foo_bar
  assert_failure
  [[ "$output" == *"duplicate key"* ]] || fail "Expected duplicate key error, got: $output"
}

@test "uppercase short cluster lowercased" {
  run parse_args -AB
  assert_success
  parsed="$output"
  _assert_key_true "$parsed" a
  _assert_key_true "$parsed" b
}

@test "duplicate short key differing only by case" {
  run parse_args -ABc -a
  assert_failure
  [[ "$output" == *"duplicate key"* ]] || fail "Expected duplicate key error, got: $output"
}

@test "positional args after option" {
  run parse_args --foo bar baz qux
  assert_success
  parsed="$output"
  run jq -r '._positional | length' <<<"$parsed"; assert_success; assert_output "2"
  run jq -r '._positional[0]' <<<"$parsed"; assert_output "baz"
  run jq -r '._positional[1]' <<<"$parsed"; assert_output "qux"
  run jq -r '.foo' <<<"$parsed"; assert_output "bar"
}

@test "end of options with --" {
  run parse_args --foo bar -- -x --y
  assert_success
  parsed="$output"
  run jq -r '._positional | length' <<<"$parsed"; assert_output "2"
  run jq -r '._positional[0]' <<<"$parsed"; assert_output "-x"
  run jq -r '._positional[1]' <<<"$parsed"; assert_output "--y"
}

