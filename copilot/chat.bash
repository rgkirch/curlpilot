# copilot/chat.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep request "copilot/request.bash"
register_dep parse_args "parse_args.bash"
register_dep parse_response "copilot/parse_response.bash"
register_dep config "config.bash"

readonly ARG_SPEC_JSON=$(echo "$(exec_dep config)" | jq '
{
  "_description": "Sends a message history to the GitHub Copilot chat API and streams the response.",
  "model": {
    "type": "string",
    "description": "Specify the AI model to use.",
    "default": (.model // "gpt-4.1")
  },
  "api_endpoint": {
    "type": "string",
    "description": "Specify the API endpoint for the chat service.",
    "default": (.api_endpoint // "https://api.githubcopilot.com/chat/completions")
  },
  "stream": {
    "type": "boolean",
    "description": "Enable or disable streaming responses.",
    "default": (.stream_enabled // true)
  },
  "messages": {
    "type": "json",
    "description": "A JSON array of messages for the chat.",
    "required": true
  }
}
')

REQUEST_TICKET_JSON="$(jq --null-input \
  --argjson spec "$ARG_SPEC_JSON" \
  '{"spec": $spec, "args": $ARGS.positional}' \
  --args -- "$@")"

PARSED_ARGS="$(exec_dep parse_args "$REQUEST_TICKET_JSON")"

if echo "$PARSED_ARGS" | jq -e 'has("help")' >/dev/null; then
  echo "$PARSED_ARGS" | jq -r '.help'
  exit 0
fi

echo "$PARSED_ARGS" \
  | jq '{model, stream_enabled: .stream, messages}' \
  | exec_dep request --body - \
  | exec_dep parse_response

echo
