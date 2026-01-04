#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"
register_dep request "client/copilot/request.bash"

readonly ARG_SPEC_JSON='{
  "input": {
    "type": "string",
    "description": "The input prompt for the model."
  },
  "tools": {
    "type": "json",
    "description": "A JSON array of tools the model may call.",
    "default": "[]"
  },
  "verbose": {
    "name": "verbose",
    "type": "bool",
    "help": "Enable verbose output, including the full curl command.",
    "default": false
  }
}'

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

readonly PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")
readonly INPUT_PROMPT=$(jq --raw-output '.input' <<< "$PARSED_ARGS")
readonly TOOLS_JSON=$(jq --raw-output '.tools' <<< "$PARSED_ARGS")
readonly VERBOSE=$(jq --raw-output '.verbose' <<< "$PARSED_ARGS")

REQUEST_BODY_JSON=$(jq -n \
  --arg input "$INPUT_PROMPT" \
  --argjson tools "$TOOLS_JSON" \
  '{input: $input, tools: $tools}')

if [[ "$VERBOSE" == "true" ]]; then
  echo "REQUEST_BODY_JSON: $REQUEST_BODY_JSON" >&2
fi

exec_dep request --body "$REQUEST_BODY_JSON" --verbose "$VERBOSE"
