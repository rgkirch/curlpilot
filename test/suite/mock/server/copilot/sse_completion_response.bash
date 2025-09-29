# curlpilot/test/mocks/server/copilot/sse_completion_response.bash
set -euo pipefail
#set -x

# This script generates a Server-Sent Events (SSE) stream to stdout.
# It uses a predefined jq filter script and takes its parameters as CLI arguments.

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../../deps.bash"

log "deps loaded"

register_dep parse_args "parse_args/parse_args.bash"

# 1. Define the schema for the command-line arguments.
readonly ARG_SPEC_JSON='{
  "message_parts": {
    "type": "json",
    "description": "Required. A JSON array of strings for each content chunk."
  },
  "prompt_tokens": {
    "type": "number",
    "default": 999
  },
  "created": {
    "type": "number",
    "default": 1758558871
  },
  "id": {
    "type": "string",
    "default": "what"
  }
}'

# 2. Build the job ticket and parse the command-line arguments.
job_ticket_json=$(jq --null-input \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

log "job ticket json: $job_ticket_json"

A="$(exec_dep parse_args "$job_ticket_json")"

log "A: $A"

jq --compact-output \
  --raw-output \
  --from-file "$(dirname "$0")"/sse_completion_response.jq <<< "$A"
