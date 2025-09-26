# copilot/request.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep auth "copilot/auth.bash"
register_dep parse_args "parse_args/parse_args.bash"
register_dep config "config.bash"

readonly ARG_SPEC_JSON='{
  "body": {
    "type": "json",
    "description": "The JSON request body."
  },
  "status_file": {
    "type": "path",
    "description": "File to write the final status JSON to.",
    "default": null
  }
}'

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

readonly PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")
readonly STATUS_FILE=$(echo "$PARSED_ARGS" | jq --raw-output '.status_file // empty')
readonly REQUEST_BODY=$(echo "$PARSED_ARGS" | jq --compact-output '.body')

CONFIG_JSON=$(exec_dep config)
API_ENDPOINT=$(echo "$CONFIG_JSON" | jq --raw-output '.api_endpoint')

if [[ -z "$API_ENDPOINT" || "$API_ENDPOINT" == "null" ]]; then
  echo "Error: Failed to get API endpoint from config." >&2
  exit 1
fi

AUTH_JSON=$(exec_dep auth)
COPILOT_SESSION_TOKEN=$(echo "$AUTH_JSON" | jq --raw-output '.session_token')

if [[ -z "$COPILOT_SESSION_TOKEN" || "$COPILOT_SESSION_TOKEN" == "null" ]]; then
  echo "Error: Failed to get auth token." >&2
  exit 1
fi

curl_args=(
  -sS -X POST
  "$API_ENDPOINT"
  -H "Content-Type: application/json"
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}"
  -H "Openai-Intent: conversation-panel"
  -H "X-Request-Id: $(uuidgen)"
  -H "Vscode-Sessionid: some-session-id"
  -H "Vscode-Machineid: some-machine-id"
  -H "Copilot-Integration-Id: vscode-chat"
  -H "Editor-Plugin-Version: gptel/*"
  -H "Editor-Version: emacs/29.1"
  -d "$REQUEST_BODY"
)

if [[ -n "$STATUS_FILE" ]]; then
  curl_args+=(--write-out "$(printf '%%output{%s}
{
  "http_code": %%{http_code},
  "exitcode": %%{exitcode},
  "errormsg": "%%{errormsg}"
}' "$STATUS_FILE")")
fi

curl "${curl_args[@]}"
