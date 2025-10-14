#!/usr/bin/env bats
# test/generate_help_text_test.bats

setup() {
  source test/test_helper.bash
  source src/logging.bash
}

@test "generate_help_text outputs expected help with defaults" {
  spec='{
    "_description": "Example tool",
    "foo_bar": {"description": "Foo bar option", "default": 42},
    "name": {"description": "Name value"}
  }'
  run jq -r --argjson spec "$spec" -f src/generate_help_text.jq <<<"{\"spec\":$spec}"
  assert_success
  # Capture output lines into array
  expected=$(cat <<'EOF'
Example tool

USAGE:
  script.sh [OPTIONS]

OPTIONS:
  --foo-bar	Foo bar option (default: 42)
  --name	Name value
EOF
)
  [ "$output" = "$expected" ] || { echo "Got:\n$output\nExpected:\n$expected" >&2; false; }
}

@test "generate_help_text errors when description missing" {
  bad='{"foo": {"default": 1}}'
  run jq -r --argjson spec "$bad" -f src/generate_help_text.jq <<<"{\"spec\":$bad}"
  assert_failure
  [[ "$output" == *"missing a string 'description'"* ]] || fail "Expected missing description error, got: $output"
}
