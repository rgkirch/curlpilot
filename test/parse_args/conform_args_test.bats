#!/usr/bin/env bats

source test/test_helper.bash

_setup() {
  source "$(dirname "$BATS_TEST_FILENAME")/../.deps.bash"
  register_dep conform_args "parse_args/conform_args.bash"
  CONFORM=$(resolve_path src/parse_args/conform_args.bash)
}

# Helper to run conform
_run_conform() {
  local spec_json="$1" parsed_json="$2"
  run bash "$CONFORM" --spec-json "$spec_json" --parsed-json "$parsed_json"
}

@test "applies defaults when absent" {
  spec='{"threshold":{"type":"number","default":0.5}}'
  _run_conform "$spec" '{}'
  assert_success
  echo "$output" | jq -e '.threshold==0.5' >/dev/null
}

@test "missing required (no default) errors" {
  spec='{"port":{"type":"integer"}}'
  _run_conform "$spec" '{}'
  assert_failure
  [[ "$output" == *"missing required argument --port"* ]] || fail "Expected missing port error"
}

@test "enum accepts valid and rejects invalid" {
  spec='{"mode":{"type":"enum","enums":["fast","safe"],"default":"fast"}}'
  _run_conform "$spec" '{"mode":"safe"}'
  assert_success
  _run_conform "$spec" '{"mode":"slow"}'
  assert_failure
  [[ "$output" == *"invalid enum"* || "$output" == *"invalid enum value"* ]] || fail "Expected enum error"
}

@test "integer valid vs number valid" {
  spec='{"port":{"type":"integer"},"threshold":{"type":"number"}}'
  _run_conform "$spec" '{"port":"9000","threshold":"0.75"}'
  assert_success
  _run_conform "$spec" '{"port":"9.1","threshold":"abc"}'
  assert_failure
  [[ "$output" == *"must be integer"* ]] || fail "Expected integer error"
}

@test "integer invalid and number invalid" {
  spec='{"port":{"type":"integer"},"threshold":{"type":"number"}}'
  _run_conform "$spec" '{"port":"9.1","threshold":"abc"}'
  assert_failure
  [[ "$output" == *"must be integer"* ]]
}


@test "boolean coercion invalid" {
  spec='{"flag":{"type":"boolean"}}'
  _run_conform "$spec" '{"flag":"banana"}'
  assert_failure
  [[ "$output" == *"invalid boolean"* ]]
}


@test "boolean coercion canonical true variants" {
  spec='{"flag":{"type":"boolean"}}'
  for v in true FALSE 0; do _run_conform "$spec" '{"flag":"'$v'"}'; assert_success || return 1; done
  _run_conform "$spec" '{"flag":"banana"}'
  assert_failure
  [[ "$output" == *"invalid boolean"* ]] || fail "Expected invalid boolean error"
}

@test "regex invalid pattern" {
  spec='{"pattern":{"type":"regex"}}'
  _run_conform "$spec" '{"pattern":"[unclosed"}'
  assert_failure
  [[ "$output" == *"invalid regex"* ]] || fail "Expected regex error"
}

@test "json must be valid" {
  spec='{"cfg":{"type":"json"}}'
  _run_conform "$spec" '{"cfg":"not json"}'
  assert_failure
  [[ "$output" == *"value contains malformed JSON"* ]] || fail "Expected json validity error"
}

@test "unknown keys ignored" {
  spec='{"cfg":{"type":"json"}}'
  _run_conform "$spec" '{"cfg":"{\"a\":1}","extra":"value"}'
  assert_success
  echo "$output" | jq -e 'has("extra") | not' >/dev/null || fail "Unexpected inclusion of unknown key"
}

@test "json type default fails if it IS a string" {
  spec='{"cfg":{"type":"json","default":"{\"a\":1}"}}'
  _run_conform "$spec" '{}'
  assert_failure
  [[ "$output" == *"default in spec must be native JSON"* ]] || fail "Expected error for stringy JSON default"
}

@test "one required provided other missing errors only missing" {
  spec='{"port":{"type":"integer"},"responses":{"type":"json"}}'
  _run_conform "$spec" '{"port":"1234"}'
  assert_failure
  [[ "$output" == *"missing required argument --responses"* ]] || fail "Expected missing responses only"
  [[ "$output" != *"missing required argument --port"* ]] || fail "Port should not be reported missing"
}

@test "default not applied when value provided" {
  spec='{"port":{"type":"integer","default":8080}}'
  _run_conform "$spec" '{"port":"9002"}'
  assert_success
  echo "$output" | jq -e '.port==9002' >/dev/null || fail "provided value overridden by default"
}

@test "multiple required only missing reported" {
  spec='{"a":{"type":"integer"},"b":{"type":"integer"},"c":{"type":"integer"}}'
  _run_conform "$spec" '{"a":"1","c":"3"}'
  assert_failure
  [[ "$output" == *"missing required argument --b"* ]] || fail "Missing b not reported"
  [[ "$output" != *"missing required argument --a"* ]] || fail "a incorrectly reported missing"
  [[ "$output" != *"missing required argument --c"* ]] || fail "c incorrectly reported missing"
}


@test "json type default succeeds if it is native JSON" {
  spec='{"cfg":{"type":"json","default":{"a":1}}}'
  _run_conform "$spec" '{}'
  assert_success
  echo "$output" | jq -e '.cfg.a == 1' >/dev/null || fail "Native JSON default was not applied correctly"
}

@test "required integer without default succeeds when provided" {
  spec='{"port":{"type":"integer"}}'
  _run_conform "$spec" '{"port":"9001"}'
  assert_success
  echo "$output" | jq -e '.port==9001' >/dev/null || fail "port not preserved"
}

@test "required multiline json and integer both provided succeed" {
  spec='{"port":{"type":"integer"},"responses":{"type":"json"}}'
  _run_conform "$spec" "{\"port\": \"42\", \"responses\": \"[\n  1,\n  2\n]\"}"
  assert_success
  echo "$output" | jq -e '.port==42 and .responses==[1,2]' >/dev/null || fail "Values not preserved $output"
}

@test "integer provided as native number not missing" {
  spec='{"port":{"type":"integer"}}'
  _run_conform "$spec" '{"port":42}'
  assert_success
  echo "$output" | jq -e '.port==42' >/dev/null || fail "Native integer lost"
}

@test "parsed json polluted by concatenated objects mis-detects missing required" {
  spec='{"port":{"type":"integer"},"responses":{"type":"json"}}'
  polluted='{"port":"5555","responses":"[1]"}{"extra":"noise"}'
  _run_conform "$spec" "$polluted"
  assert_failure
  [[ "$output" == *"missing required argument --port"* ]] || fail "Expected port falsely missing"
  [[ "$output" == *"missing required argument --responses"* ]] || fail "Expected responses falsely missing"
}

@test "required json without default succeeds when provided" {
  spec='{"cfg":{"type":"json"}}'
  _run_conform "$spec" '{"cfg":"{\"x\":2}"}'
  assert_success
  echo "$output" | jq -e '.cfg.x==2' >/dev/null || fail "cfg.x not parsed"
}

@test "json multiline value" {
  spec='{"responses":{"type":"json"}}'
  multiline="{\"responses\": \"[\n  1,\n  2\n]\"}"
  _run_conform "$spec" "$multiline"
  assert_success
  echo "$output" | jq -e '.responses==[1,2]' >/dev/null || fail "responses not parsed"
}
