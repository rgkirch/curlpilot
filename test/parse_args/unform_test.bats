#!/usr/bin/env bats
# -*- mode: bats; -*-
#test/parse_args/unform_test.bats

source test/test_helper.bash
source src/logging.bash

conform() {
  source deps.bash
  source test/test_helper.bash

  _exec_dep "$PROJECT_ROOT/src/parse_args/conform_args.bash" conform_args "$@"
}

unform() {
  source deps.bash
  source test/test_helper.bash

  _exec_dep "$PROJECT_ROOT/src/parse_args/unform.bash" unform "$@"
}



# Represents the raw output from parse_args_specless.bash (all strings)


# Represents the final, correctly typed output from conform_args.bash


# Helper to compare two JSON strings canonically (sorted keys)
deep_assert_json_equal() {
  local actual="$1"
  local expected="$2"

  # Canonicalize the JSON by sorting keys AND by parsing any string values
  # that are themselves valid JSON. This makes the comparison robust against
  # formatting differences both in the structure and within string-encoded JSON.
  local canonical_actual
  canonical_actual=$(echo "$actual" | jq -S 'walk(if type == "string" then (try fromjson catch .) else . end)')

  local canonical_expected
  canonical_expected=$(echo "$expected" | jq -S 'walk(if type == "string" then (try fromjson catch .) else . end)')

  assert_equal "$canonical_actual" "$canonical_expected"
}

@test "round trip integer boolean json string" {
  spec='{"port":{"type":"integer"},"flag":{"type":"boolean"},"cfg":{"type":"json"},"name":{"type":"string"}}'
  raw='{"port":"9090","flag":"true","cfg":"{\"a\":1, \"b\":[2,3]}","name":"test-server"}'
  run conform --spec-json "$spec" --parsed-json "$raw"; assert_success; conformed="$output"
  run unform --spec-json "$spec" --parsed-json "$conformed"; assert_success; unformed="$output"
  deep_assert_json_equal "$unformed" "$raw"
}

@test "unform from conformed preserves json string encoding" {
  spec='{"cfg":{"type":"json"}}'
  conformed='{"cfg":{"a":1}}'
  run unform --spec-json "$spec" --parsed-json "$conformed"; assert_success; out="$output"
  run jq -r '.cfg' <<<"$out"; assert_output '{"a":1}'
}

@test "unform boolean true becomes string true" {
  spec='{"flag":{"type":"boolean"}}'
  conformed='{"flag":true}'
  run unform --spec-json "$spec" --parsed-json "$conformed"; assert_success; out="$output"
  run jq -r '.flag' <<<"$out"; assert_output 'true'
}

@test "unform integer becomes numeric string" {
  spec='{"port":{"type":"integer"}}'
  conformed='{"port":1234}'
  run unform --spec-json "$spec" --parsed-json "$conformed"; assert_success; out="$output"
  run jq -r '.port' <<<"$out"; assert_output '1234'
}

@test "missing spec key is ignored" {
  spec='{"a":{"type":"string"}}'
  conformed='{"a":"x","b":1}'
  run unform --spec-json "$spec" --parsed-json "$conformed"; assert_success; out="$output"
  run jq 'has("b")' <<<"$out"; assert_output 'false'
}

@test "invalid spec json errors" {
  run unform --spec-json '{bad' --parsed-json '{}' ; assert_failure
  [[ "$output" == *"spec is not valid JSON"* ]] || fail "$output"
}

@test "invalid conformed json errors" {
  run unform --spec-json '{}' --parsed-json '{bad' ; assert_failure
  [[ "$output" == *"conformed data is not valid JSON"* ]] || fail "$output"
}
