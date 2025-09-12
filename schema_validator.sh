#!/bin/bash
set -euo pipefail

# This script validates a JSON stream from stdin against a given JSON schema file.
# It acts as a wrapper around the 'ajv-cli' tool.

# --- Dependency Check ---
# Ensure ajv is installed and available in the system's PATH.
if ! command -v ajv &> /dev/null; then
  echo "Error: The command 'ajv' is not found." >&2
  echo "Please install it globally by running: npm install -g ajv-cli" >&2
  exit 127
fi

# --- Argument Validation ---
# The script requires exactly one argument: the path to the schema file.
if [[ -z "${1-}" ]]; then
  echo "Usage: <json_stream> | $0 <path_to_schema.json>" >&2
  exit 1
fi

SCHEMA_FILE="$1"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Error: Schema file not found at '$SCHEMA_FILE'" >&2
  exit 1
fi

# --- Execute Validation ---
# Use 'ajv' to validate the data from stdin ('-d -') against the schema.
# The '--errors=text' flag provides human-readable output on failure.
# ajv is silent and exits with 0 on success.
# On failure, it prints errors to stderr and exits with a non-zero code.
ajv validate --schema "$SCHEMA_FILE" --data - --errors=text
