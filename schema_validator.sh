#!/bin/bash
set -euo pipefail

# curlpilot/schema_validator.sh

#
# Validates a JSON object against a schema, applying defaults and checking requirements.
#
# Usage: ./validate_args.sh <spec_json_string> <data_json_string>
#
# The spec_json is an object where each key is the snake_case name of an
# argument, and the value is an object describing the argument:
# {
#   "my_arg": {
#     "type": "string" | "boolean" | "path",
#     "description": "Help text for the user.",
#     "required": false,
#     "default": "some_value"
#   }
# }
#

# --- UTILITY FUNCTIONS ---

# Abort with a message.
abort() {
  echo "Validation Error: $1" >&2
  exit 1
}

# Convert snake_case to kebab-case for displaying help text.
snake_to_kebab() {
  echo "$1" | sed 's/_/-/g'
}

# --- MAIN LOGIC ---

# Input validation
[[ "$#" -ne 2 ]] && abort "Usage: $0 <schema_json> <data_json>"
SCHEMA_JSON="$1"
DATA_JSON="$2"

# Check if inputs are valid JSON
echo "$SCHEMA_JSON" | jq -e . >/dev/null || abort "Schema is not valid JSON."
echo "$DATA_JSON" | jq -e . >/dev/null || abort "Data is not valid JSON."

# Start with the user-provided data
FINAL_JSON="$DATA_JSON"

# Get all the keys defined in the schema specification
SPEC_KEYS=$(echo "$SCHEMA_JSON" | jq -r 'keys[]')

# Loop through each key from the schema to validate and apply defaults
for key in $SPEC_KEYS; do
  SPEC_ITEM=$(echo "$SCHEMA_JSON" | jq --arg key "$key" '.[$key]')
  EXPECTED_TYPE=$(echo "$SPEC_ITEM" | jq -r '.type')
  IS_REQUIRED=$(echo "$SPEC_ITEM" | jq -r '.required // "false"')
  DEFAULT_VALUE=$(echo "$SPEC_ITEM" | jq '.default') # Keep as JSON literal

  # Check if the user provided this argument
  if [[ $(echo "$DATA_JSON" | jq --arg key "$key" 'has($key)') == "true" ]]; then
    VALUE=$(echo "$DATA_JSON" | jq --arg key "$key" '.[$key]')
    ACTUAL_TYPE=$(echo "$VALUE" | jq -r 'type')

    # --- Type Validation ---
    VALID=false
    if [[ "$EXPECTED_TYPE" == "$ACTUAL_TYPE" ]]; then
      VALID=true
    # Allow path types to be validated as strings
    elif [[ "$EXPECTED_TYPE" == "path" && "$ACTUAL_TYPE" == "string" ]]; then
      VALID=true
    fi

    if [[ "$VALID" == "false" ]]; then
        FLAG_NAME=$(snake_to_kebab "$key")
        abort "Type mismatch for '--$FLAG_NAME'. Expected '$EXPECTED_TYPE' but received '$ACTUAL_TYPE'."
    fi

  else
    # The user did not provide the argument
    if [[ "$IS_REQUIRED" == "true" ]]; then
      FLAG_NAME=$(snake_to_kebab "$key")
      abort "Required argument '--$FLAG_NAME' is missing."
    fi

    # Apply default value if one is defined in the spec
    if [[ "$DEFAULT_VALUE" != "null" ]]; then
      FINAL_JSON=$(echo "$FINAL_JSON" | jq --arg key "$key" --argjson val "$DEFAULT_VALUE" '.[$key] = $val')
    fi
  fi
done

# --- OUTPUT ---
echo "$FINAL_JSON"
