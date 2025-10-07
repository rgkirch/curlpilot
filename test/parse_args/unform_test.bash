#!/usr/bin/env bats

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/../.deps.bash"
  source "$(dirname "$BATS_TEST_FILENAME")/../test_helper.bash"

  register_dep conform_args "parse_args/conform_args.bash"
  register_dep unform_args "parse_args/unform.bash"

  CONFORM=$(resolve_path src/parse_args/conform_args.bash)
  UNFORM=$(resolve_path src/parse_args/unform.bash)
}

_spec_base='{
  "port": {"type": "integer"},
  "flag": {"type": "boolean"},
  "cfg": {"type": "json"},
  "name": {"type": "string"}
}'

# Represents the raw output from parse_args_specless.bash (all strings)
_parsed_base='{
  "port": "9090",
  "flag": "true",
  "cfg": "{\"a\":1, \"b\":[2,3]}",
  "name": "test-server"
}'

# Represents the final, correctly typed output from conform_args.bash
_conformed_base='{
  "port": 9090,
  "flag": true,
  "cfg": {"a":1, "b":[2,3]},
  "name": "test-server"
}'

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

@test "conform -> unform round trip" {
  run bash "$CONFORM" --spec-json "$_spec_base" --parsed-json "$_parsed_base"
  assert_success
  local conformed_output="$output"

  run bash "$UNFORM" --spec-json "$_spec_base" --parsed-json "$conformed_output"
  assert_success
  local unformed_output="$output"

  deep_assert_json_equal "$unformed_output" "$_parsed_base"
}

@test "unform -> conform round trip" {
  run bash "$UNFORM" --spec-json "$_spec_base" --parsed-json "$_conformed_base"
  assert_success
  local unformed_output="$output"

  run bash "$CONFORM" --spec-json "$_spec_base" --parsed-json "$unformed_output"
  assert_success
  local conformed_output="$output"

  deep_assert_json_equal "$conformed_output" "$_conformed_base"
}
