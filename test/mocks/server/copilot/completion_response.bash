# test/mocks/server/copilot/completion_response.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../deps.bash"

register_dep parse_args "parse_args.bash"

readonly ARG_SPEC_JSON='{
  "message_content": {
    "type": "string",
    "description": "The AI response.",
    "default": "This is a mock Copilot response."
  },
  "completion_tokens": {
    "type": "number",
    "description": "Override the calculated completion tokens."
  },
  "prompt_tokens": {
    "type": "number",
    "description": "Override the default prompt tokens."
  }
}'

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

exec_dep parse_args "$job_ticket_json" | \
  jq --compact-output '{message_content, completion_tokens, prompt_tokens}' | \
  jq -f "$(dirname "$0")"/completion_response.jq
