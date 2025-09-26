# copilot/chat.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep request "copilot/request.bash"
register_dep parse_args "parse_args/parse_args.bash"
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
    "description": "A JSON array of messages for the chat."
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

# 1. Create a temporary directory to hold status and response files.
TEMP_DIR=$(mktemp -d)

# 2. Define file paths within the new directory.
STATUS_FILE="$TEMP_DIR/status.json"
RESPONSE_BODY_FILE="$TEMP_DIR/response.body"

# 3. Set a trap to ensure the entire temporary directory is cleaned up on exit.
trap 'rm -rf "$TEMP_DIR"' EXIT

# 4. Execute the request, providing the --status-file flag and saving the body.
echo "$PARSED_ARGS" \
  | jq --compact-output '{model, stream_enabled: .stream, messages}' \
  | exec_dep request --body - --status-file "$STATUS_FILE" > "$RESPONSE_BODY_FILE"

# 5. Check the HTTP status code from the status file.
HTTP_CODE=$(jq -r '.http_code' "$STATUS_FILE")

if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "Error: API request failed with HTTP status ${HTTP_CODE}." >&2
  # The response body often contains a detailed error message from the API.
  cat "$RESPONSE_BODY_FILE" >&2
  exit 1
fi

# 6. If the request was successful, parse the response body using the --response flag.
exec_dep parse_response --response "$(cat "$RESPONSE_BODY_FILE")"

echo
