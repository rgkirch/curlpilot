#!/bin/bash

set -euo pipefail

# This script generates a mock Copilot API response in JSON format.
# All logic, including static JSON objects, is defined inside the jq recipe.
# Usage: echo '{"message_content": "..."}' | ./completion_response.sh

# Generate the JSON response using jq
JSON_RESPONSE=$(jq -f "$(dirname "$0")"/completion_response.jq)

# Path to the JSON schema
SCHEMA_PATH="$(dirname "$0")"/completion_response.output.schema.json

# Validate the JSON response against the schema using ajv-cli
if ! command -v ajv &> /dev/null
then
    echo "Error: ajv-cli is not installed. Please install it globally: npm install -g ajv-cli" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
TEMP_JSON_FILE="$TEMP_DIR/response.json"
echo "$JSON_RESPONSE" > "$TEMP_JSON_FILE"
ajv validate -s "$SCHEMA_PATH" -d "$TEMP_JSON_FILE" 1>&2

# If validation passes, print the JSON response followed by the status block
if [ $? -eq 0 ]; then
    # Print the main body
    echo "$JSON_RESPONSE"
    # Print the null separator and the status JSON
    printf '\0%s\n' '{"http_code": 200, "exitcode": 0, "errormsg": ""}'
else
    echo "JSON validation failed against schema: $SCHEMA_PATH" >&2
    exit 1
fi
