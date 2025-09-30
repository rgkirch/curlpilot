# copilot/chat.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep request "gemini/request.bash"
register_dep parse_args "parse_args/parse_args.bash"
register_dep parse_response "gemini/parse_response.bash"
register_dep config "config.bash"

readonly ARG_SPEC_JSON=$(echo "$(exec_dep config)" | jq '
{
  "_description": "Sends a message history to the GitHub Copilot chat API and streams the response.",
  "model": {
    "type": "string",
    "description": "Specify the AI model to use.",
    "default": (.gemini.model // "gemini-2.5-flash")
  },
  "api_endpoint": {
    "type": "string",
    "description": "Specify the API endpoint for the chat service.",
    "default": (.gemini.api_endpoint // "https://cloudcode-pa.googleapis.com/v1internal:generateContent")
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

log "making the request"

# 4. Execute the request, providing the --status-file flag and saving the body.
AUTH_INFO=$(exec_dep auth)
ACCESS_TOKEN=$(jq --raw-output '.access_token' <<< "$AUTH_INFO")
PROJECT_ID=$(jq --raw-output '.project_id' <<< "$AUTH_INFO")

readonly API_ENDPOINT=$(jq -r '.api_endpoint' <<< "$PARSED_ARGS")

# Ensure ACCESS_TOKEN and PROJECT_ID are not empty
if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "Error: Failed to get access token." >&2
  exit 1
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "Error: Failed to get project ID." >&2
  exit 1
fi

# Pass ACCESS_TOKEN to request.bash via environment variable for now, as request.bash expects it from auth.bash
# This will be refactored later if request.bash is made to accept ACCESS_TOKEN as an argument.
export ACCESS_TOKEN

# The rest of the script remains the same for now, but will be updated to use the new PROJECT_ID and API_ENDPOINT

echo "$PARSED_ARGS" \
  | jq --compact-output --arg project_id "$PROJECT_ID" \
    '{model, project: $project_id, request: {contents: .messages | map({role, parts: [{text: .content}]})}}' \
  | exec_dep request --body - --api_endpoint "$API_ENDPOINT" --status-file "$STATUS_FILE" > "$RESPONSE_BODY_FILE"

# 5. Check the HTTP status code from the status file.
HTTP_CODE=$(jq -r '.http_code' "$STATUS_FILE")

if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "Error: API request failed with HTTP status ${HTTP_CODE}." >&2
  # The response body often contains a detailed error message from the API.
  cat "$RESPONSE_BODY_FILE" >&2
  exit 1
fi

log "parsing the response"

# 6. If the request was successful, parse the response body using the --response flag.
exec_dep parse_response --response "$(cat "$RESPONSE_BODY_FILE")"
