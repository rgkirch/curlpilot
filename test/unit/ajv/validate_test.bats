#!/usr/bin/env bats

source "$(dirname "$BATS_TEST_FILENAME")/.deps.bash"

source "$BATS_TEST_DIRNAME/../../test_helper.bash"

VALIDATE_SCRIPT_PATH="$PROJECT_ROOT/ajv/validate.js"

# Bats provides a temporary directory for each test file, available as $BATS_TEST_TMPDIR.
# It's automatically created and cleaned up, so manual setup and teardown are not needed.

# ===============================================
# ==           TEST CASES                      ==
# ===============================================

@test "Valid data succeeds" {
  # Arrange: Create the schema and data files for this specific test.
  local schema_file="$BATS_TEST_TMPDIR/schema.json"
  local data_file="$BATS_TEST_TMPDIR/data.json"

  cat > "$schema_file" <<EOL
{
  "type": "object",
  "properties": { "name": { "type": "string" }, "age": { "type": "number" } },
  "required": ["name", "age"]
}
EOL
  cat > "$data_file" <<EOL
{ "name": "John Doe", "age": 30 }
EOL

  # Act: Run the validation script.
  run node "$VALIDATE_SCRIPT_PATH" "$schema_file" "$data_file"

  # Assert: Check for a successful exit code and the correct output.
  assert_success
  assert_output --partial "✅ Data is valid!"
}

@test "Invalid data (wrong type) fails" {
  local schema_file="$BATS_TEST_TMPDIR/schema.json"
  local data_file="$BATS_TEST_TMPDIR/data.json"

  cat > "$schema_file" <<EOL
{
  "type": "object",
  "properties": { "name": { "type": "string" }, "age": { "type": "number" } },
  "required": ["name", "age"]
}
EOL
  cat > "$data_file" <<EOL
{ "name": "Jane Doe", "age": "twenty-five" }
EOL

  run node "$VALIDATE_SCRIPT_PATH" "$schema_file" "$data_file"

  assert_failure
  assert_output --partial "❌ Data is invalid:"
}

@test "Invalid data (missing required property) fails" {
  local schema_file="$BATS_TEST_TMPDIR/schema.json"
  local data_file="$BATS_TEST_TMPDIR/data.json"

  cat > "$schema_file" <<EOL
{
  "type": "object",
  "properties": { "name": { "type": "string" }, "age": { "type": "number" } },
  "required": ["name", "age"]
}
EOL
  cat > "$data_file" <<EOL
{ "name": "Jane Doe" }
EOL

  run node "$VALIDATE_SCRIPT_PATH" "$schema_file" "$data_file"

  assert_failure
  assert_output --partial "❌ Data is invalid:"
}

@test "Non-existent schema file fails" {
  local data_file="$BATS_TEST_TMPDIR/data.json"
  cat > "$data_file" <<EOL
{ "name": "John Doe", "age": 30 }
EOL

  run node "$VALIDATE_SCRIPT_PATH" "$BATS_TEST_TMPDIR/nonexistent.json" "$data_file"

  assert_failure
  assert_output --partial "An error occurred"
}

@test "Malformed data file fails" {
  local schema_file="$BATS_TEST_TMPDIR/schema.json"
  local data_file="$BATS_TEST_TMPDIR/data.json"

  cat > "$schema_file" <<EOL
{
  "type": "object",
  "properties": { "name": { "type": "string" }, "age": { "type": "number" } },
  "required": ["name", "age"]
}
EOL
  cat > "$data_file" <<EOL
{ "name": "Bad JSON", "age": 40, }
EOL

  run node "$VALIDATE_SCRIPT_PATH" "$schema_file" "$data_file"

  assert_failure
  assert_output --partial "An error occurred"
}

@test "No arguments shows usage message" {
  run node "$VALIDATE_SCRIPT_PATH"

  log "VALIDATE_SCRIPT_PATH: VALIDATE_SCRIPT_PATH"
  assert_failure
  assert_output --partial "Usage: node validate.js"
}
