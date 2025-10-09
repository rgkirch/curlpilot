#!/usr/bin/env bats

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"
  source "$(dirname "$BATS_TEST_FILENAME")/../test_helper.bash"
  register_dep parse_args_specless "parse_args/parse_args_specless.bash"
  PARSER=$(resolve_path src/parse_args/parse_args_specless.bash)
  log_debug "PARSER $PARSER"
}

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
  run bash "$PARSER" --foo --bar
  assert_success
  parsed="$output"
  _assert_key_true "$parsed" foo
  _assert_key_true "$parsed" bar
}

@test "long separated value" {
  run bash "$PARSER" --name value
  assert_success
  _assert_key_string "$output" name value
}

@test "dash-leading value via equals" {
  run bash "$PARSER" --pattern=--abc
  assert_success
  _assert_key_string "$output" pattern --abc
}

@test "short cluster letters" {
  run bash "$PARSER" -abc
  assert_success
  log_trace "output $output"
  parsed="$output"
  _assert_key_true "$parsed" a
  _assert_key_true "$parsed" b
  _assert_key_true "$parsed" c
}

@test "error on digit in short cluster" {
  run bash "$PARSER" -ab1
  assert_failure
  [[ "$output" == *"invalid short option cluster"* ]] || fail "Expected invalid cluster error, got: $output"
}

@test "error on duplicate key" {
  run bash "$PARSER" --foo --foo
  assert_failure
  [[ "$output" == *"duplicate key"* ]] || fail "Expected duplicate key error, got: $output"
}

@test "normalization of dashed long key" {
  run bash "$PARSER" --foo-bar
  assert_success
  _assert_key_true "$output" foo_bar
}

@test "empty value with equals" {
  run bash "$PARSER" --empty=
  assert_success
  _assert_key_string "$output" empty ""
}

@test "stray value error" {
  run bash "$PARSER" value_only
  assert_failure
  [[ "$output" == *"stray value"* ]] || fail "Expected stray value error, got: $output"
}

@test "boolean flag before short cluster treated separately" {
  run bash "$PARSER" --flag -xy
  assert_success
  parsed="$output"
  _assert_key_true "$parsed" flag
  _assert_key_true "$parsed" x
  _assert_key_true "$parsed" y
}

@test "negative number requires equals form" {
  run bash "$PARSER" --num=-10
  assert_success
  _assert_key_string "$output" num -10
  run bash "$PARSER" --num -10
  assert_failure
  [[ "$output" == *"invalid short option cluster"* || "$output" == *"value for --num starts with"* ]] || fail "Expected error for separated negative number, got: $output"
}

# @test "long separated value with newlines" {
#   multiline_val='"[\n  \"/tmp/bats-run-52tUAo/test/1/r1.http\",\n  \"/tmp/bats-run-52tUAo/test/1/r2.http\"\n]"'
#   log_debug '"[\n  \"/tmp/bats-run-52tUAo/test/1/r1.http\",\n  \"/tmp/bats-run-52tUAo/test/1/r2.http\"\n]"'
#   run bash "$PARSER" "\"--responses\"" "$multiline_val" "\"--request_dir\"" "/tmp/bats-run-q9sMj1/test/1/requests" "\"--stdout_log\"" "\"3\"" "--stderr_log" "\"3\"" "--port" 64799
#   assert_success
#   _assert_key_string "$output" responses "$multiline_val"
# }


@test "quotes don't make values different" {
  run bash "$PARSER" --foo "bar"
  assert_success
  parsed="$output"
  _assert_key_string "$parsed" foo bar
}

@test "value is a simple JSON array string" {
  local json_val='["bar", "baz"]'
  run bash "$PARSER" --foo "$json_val"
  assert_success
  _assert_key_string "$output" foo "$json_val"
}

@test "value is a JSON object string with newlines" {
  # Create a multi-line JSON string as the value
  local json_val
  json_val=$(jq . <<<'{"key1": "value1", "key2": ["a", "b"]}')

  run bash "$PARSER" --data "$json_val"
  assert_success
  _assert_key_string "$output" data "$json_val"
}
