#!/usr/bin/env bats

setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/../.deps.bash"
  source "$(dirname "$BATS_TEST_FILENAME")/../test_helper.bash"
  register_dep conform_args "parse_args/conform_args.bash"
  CONFORM=$(resolve_path src/parse_args/conform_args.bash)
}

_spec_base='{
  "port": {"type": "integer", "default": 8080},
  "mode": {"type": "enum", "enums": ["fast", "safe"], "default": "fast"},
  "threshold": {"type": "number", "default": 0.5},
  "flag": {"type": "boolean"},
  "pattern": {"type": "regex", "default": ".*"},
  "cfg": {"type": "json"},
  "pathopt": {"type": "path", "default": "./somewhere"}
}'

# Helper to run conform
_run_conform() {
  local spec_json="$1" parsed_json="$2"
  run bash "$CONFORM" --spec-json "$spec_json" --parsed-json "$parsed_json"
}

@test "applies defaults when absent" {
  _run_conform "$_spec_base" '{"flag":true,"cfg":"{\"a\":1}"}'
  assert_success
  echo "$output" | jq -e '.port==8080 and .mode=="fast" and .threshold==0.5 and .flag==true and .pattern==".*" and .cfg.a==1' >/dev/null
}

@test "missing required (no default) errors" {
  # Remove default on port to make it required
  spec=$(echo "$_spec_base" | jq 'del(.port.default)')
  _run_conform "$spec" '{"flag":true,"cfg":"{\"a\":1}"}'
  assert_failure
  [[ "$output" == *"missing required argument --port"* ]] || fail "Expected missing port error"
}

@test "enum accepts valid and rejects invalid" {
  _run_conform "$_spec_base" '{"mode":"safe","flag":true,"cfg":"{\"a\":1}"}'
  assert_success
  _run_conform "$_spec_base" '{"mode":"slow","flag":true,"cfg":"{\"a\":1}"}'
  assert_failure
  [[ "$output" == *"invalid enum"* || "$output" == *"invalid enum value"* ]] || fail "Expected enum error"
}

@test "integer vs number validation" {
  spec=$(echo "$_spec_base" | jq '.port.type="integer" | .threshold.type="number"')
  _run_conform "$spec" '{"port":"9000","threshold":"0.75","flag":true,"cfg":"{\"a\":1}"}'
  assert_success
  _run_conform "$spec" '{"port":"9.1","threshold":"abc","flag":true,"cfg":"{\"a\":1}"}'
  assert_failure
  [[ "$output" == *"must be integer"* ]] || fail "Expected integer error"
}

@test "boolean coercion variants" {
  _run_conform "$_spec_base" '{"flag":"true","cfg":"{\"a\":1}"}'
  assert_success
  _run_conform "$_spec_base" '{"flag":"FALSE","cfg":"{\"a\":1}"}'
  assert_success
  _run_conform "$_spec_base" '{"flag":"0","cfg":"{\"a\":1}"}'
  assert_success
  _run_conform "$_spec_base" '{"flag":"banana","cfg":"{\"a\":1}"}'
  assert_failure
  [[ "$output" == *"invalid boolean"* ]] || fail "Expected invalid boolean error"
}

@test "regex invalid pattern" {
  _run_conform "$_spec_base" '{"pattern":"[unclosed","flag":true,"cfg":"{\"a\":1}"}'
  assert_failure
  [[ "$output" == *"invalid regex"* ]] || fail "Expected regex error"
}

@test "json must be valid" {
  _run_conform "$_spec_base" '{"cfg":"not json","flag":true}'
  assert_failure
  [[ "$output" == *"value is not valid JSON"* ]] || fail "Expected json validity error"
}

@test "unknown keys ignored" {
  _run_conform "$_spec_base" '{"flag":true,"cfg":"{\"a\":1}","extra":"value"}'
  assert_success
  echo "$output" | jq -e 'has("extra") | not' >/dev/null || fail "Unexpected inclusion of unknown key"
}
