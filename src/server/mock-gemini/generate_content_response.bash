#!/bin/bash
set -euo pipefail

# Assuming this file is in the same directory structure
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"

# Define the command-line arguments for the Gemini mock response.
readonly ARG_SPEC_JSON='{
  "text": {
    "type": "string",
    "description": "The AI response text.",
    "default": "Why did the scarecrow win an award?\n\nBecause he was outstanding in his field!"
  },
  "create_time": {
    "type": "string",
    "description": "ISO 8601 timestamp. Defaults to the current time if empty.",
    "default": ""
  },
  "prompt_tokens": {
    "type": "number",
    "description": "Override the default prompt tokens.",
    "default": "5"
  },
  "thoughts_tokens": {
    "type": "number",
    "description": "Override the default thoughts tokens.",
    "default": "24"
  }
}'

# 1. Use parse_args to process command-line flags based on the spec.
# 2. Pipe the resulting JSON to a jq filter to select only the needed keys.
# 3. Pipe that clean JSON object to the main jq template script.
job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

exec_dep parse_args "$job_ticket_json" | \
  jq --compact-output '{text, create_time, prompt_tokens, thoughts_tokens}' | \
  jq -f "$(dirname "$0")"/generate_content_response.jq
