# copilot/parse_response.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"

readonly ARG_SPEC_JSON='{
  "_description": "Parses a Copilot chat completion stream, extracting the content.",
  "response": {
    "type": "string",
    "description": "The chat completion response stream to parse. Use '\''-'\'' to read from stdin."
  }
}'

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

RESPONSE_DATA=$(jq -r '.response' <<< "$PARSED_ARGS")

jq --raw-output '.response.candidates[0].content.parts[0].text' <<< "$RESPONSE_DATA"
