# curlpilot/test/mocks/server/copilot/sse_completion_response.bash
set -euo pipefail

# This script generates a Server-Sent Events (SSE) stream to stdout.
# It uses a predefined jq filter script and takes its parameters as CLI arguments.

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../deps.bash"
register_dep parse_args "parse_args.bash"

# 1. Define the schema for the command-line arguments.
readonly ARG_SPEC_JSON='{
  "message_parts": {
    "type": "json",
    "description": "Required. A JSON array of strings for each content chunk.",
    "required": true
  },
  "prompt_tokens": { "type": "number", "required": true },
  "created": { "type": "number", "required": true },
  "id": { "type": "string", "required": true }
}'

# 2. Build the job ticket and parse the command-line arguments.
job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

exec_dep parse_args "$job_ticket_json" | \
    jq -c -r -f "$(dirname "$0")"/sse_completion_response.jq
