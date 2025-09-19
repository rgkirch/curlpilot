#!/usr/bin/env bash

# This script is a wrapper that uses 'parse_args.jq' to parse arguments.
# It requires one argument: a JSON string '{ "spec": {...}, "args": [...] }'.
# Standard input is passed through to the jq script.

# Exit immediately if a command exits with a non-zero status or if a variable is unset.
set -e -u -o pipefail

## --- Pre-flight Checks ---

# 1. Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to run this script." >&2
    exit 1
fi

# 2. Check for the correct number of arguments
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 '{\"spec\": {...}, \"args\": [...] }'" >&2
    echo "Example: cat my_data.json | $0 '{\"spec\": {\"file\": {\"type\": \"string\"}}, \"args\": [\"--file=-\"]}'" >&2
    exit 1
fi

# 3. Locate the accompanying .jq script
# This ensures the script can be called from any directory.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
JQ_SCRIPT_PATH="$SCRIPT_DIR/parse_args.jq"

if [[ ! -f "$JQ_SCRIPT_PATH" ]]; then
    echo "Error: The required script 'parse_args.jq' was not found in the same directory as this script." >&2
    exit 1
fi

## --- Argument Extraction ---

JSON_INPUT=$1
SPEC_JSON=$(echo "$JSON_INPUT" | jq -c '.spec')
ARGS_JSON=$(echo "$JSON_INPUT" | jq -c '.args')

## --- Execution ---

# Run the external jq script using the -f flag.
# Stdin is passed through to jq for the `input` builtin to use.
jq -n \
  --argjson spec "$SPEC_JSON" \
  --argjson args "$ARGS_JSON" \
  -f "$JQ_SCRIPT_PATH"
