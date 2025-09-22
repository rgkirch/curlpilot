# copilot/parse_response.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep parse_args "parse_args.bash"

readonly ARG_SPEC_JSON='{
  "_description": "Parses a Copilot chat completion stream, extracting the content.",
  "response": {
    "type": "string",
    "description": "The chat completion response stream to parse. Use '\''-'\'' to read from stdin."
  }
}'

# If the script is called without arguments, default to reading from stdin
# to maintain its original pipe-friendly behavior.
if [[ "$#" -eq 0 ]]; then
  set -- --response -
fi

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

# The `parse_args` script will automatically read from stdin if the
# value for --response is "-".
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

RESPONSE_DATA=$(echo "$PARSED_ARGS" | jq -r '.response')

echo "$RESPONSE_DATA" | \
  grep -v '^data: \[DONE\]$' | \
  sed 's/^data: //' | \
  jq --unbuffered --raw-output --join-output \
    '.choices[0].delta.content // .choices[0].message.content // ""'
