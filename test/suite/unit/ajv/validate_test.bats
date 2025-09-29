#!/usr/bin/env bats

# 1. Source the project's main dependency script first.
#    This defines the $PROJECT_ROOT variable. The path is relative to this test file.
source "$(dirname "$BATS_TEST_FILENAME")/../../deps.bash"

# 2. Now, use the reliable $PROJECT_ROOT to load the Bats helper libraries.
#    This will work no matter where the `bats` command is run from.
load "$PROJECT_ROOT/test/test_helper/bats-support/load.bash"
load "$PROJECT_ROOT/test/test_helper/bats-assert/load.bash"

# 3. Define the path to the script under test using $PROJECT_ROOT for robustness.
VALIDATE_SCRIPT_PATH="$PROJECT_ROOT/ajv/validate.js"

# Bats provides a temporary directory for each test file, available as $BATS_TMPDIR.
# It's automatically created and cleaned up, so manual setup and teardown are not needed.

# ===============================================
# ==           TEST CASES                      ==
# ===============================================

@test "Valid data succeeds" {
  # Arrange: Create the schema and data files for this specific test.
  local schema_file="$BATS_TMPDIR/schema.json"
  local data_file="$BATS_TMPDIR/data.json"

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
  local schema_file="$BATS_TMPDIR/schema.json"
  local data_file="$BATS_TMPDIR/data.json"

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
  local schema_file="$BATS_TMPDIR/schema.json"
  local data_file="$BATS_TMPDIR/data.json"

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
  local data_file="$BATS_TMPDIR/data.json"
  cat > "$data_file" <<EOL
{ "name": "John Doe", "age": 30 }
EOL

  run node "$VALIDATE_SCRIPT_PATH" "$BATS_TMPDIR/nonexistent.json" "$data_file"

  assert_failure
  assert_output --partial "An error occurred"
}

@test "Malformed data file fails" {
  local schema_file="$BATS_TMPDIR/schema.json"
  local data_file="$BATS_TMPDIR/data.json"

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

  # A well-behaved CLI tool should exit with an error code on bad invocation.
  assert_failure
  assert_output --partial "Usage: node validate.js"
}
