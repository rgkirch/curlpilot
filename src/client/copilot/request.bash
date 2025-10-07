# copilot/request.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep auth "client/copilot/auth.bash"
register_dep parse_args "parse_args/parse_args.bash"
register_dep config "config.bash"
log_debug "dependencies registered"

readonly ARG_SPEC_JSON='{
  "body": {
    "type": "json",
    "schema": "schemas/extracted/chat_completion_request.schema.json",
    "description": "The JSON request body."
  },
  "status_file": {
    "type": "path",
    "description": "File to write the final status JSON to.",
    "default": null
  },
  "verbose": {
    "type": "boolean",
    "description": "Enable verbose output, including the full curl command.",
    "default": false
  }
}'

log_debug "ARG_SPEC_JSON $ARG_SPEC_JSON"
log_debug "args $@"

job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  --compact-output \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")

log_debug "$$ $? job_ticket_json $job_ticket_json"

if ! PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json"); then
    echo "Error: Failed to parse arguments. Aborting." >&2
    exit 1
fi

log_debug "$$ $? PARSED_ARGS $PARSED_ARGS"

readonly STATUS_FILE=$(jq --raw-output '.status_file // empty' <<< "$PARSED_ARGS")
readonly REQUEST_BODY=$(jq --compact-output '.body' <<< "$PARSED_ARGS")
readonly VERBOSE=$(jq --raw-output '.verbose' <<< "$PARSED_ARGS")

CONFIG_JSON=$(exec_dep config)

log_debug "CONFIG_JSON $CONFIG_JSON"

API_ENDPOINT=$(jq --raw-output '.copilot.api_endpoint' <<< "$CONFIG_JSON")

log_debug "API_ENDPOINT $API_ENDPOINT"

if [[ -z "$API_ENDPOINT" || "$API_ENDPOINT" == "null" ]]; then
  echo "Error: Failed to get API endpoint from config." >&2
  exit 1
fi

AUTH_JSON=$(exec_dep auth)
COPILOT_SESSION_TOKEN=$(jq --raw-output '.session_token' <<< "$AUTH_JSON")

log_debug "COPILOT_SESSION_TOKEN: $COPILOT_SESSION_TOKEN"

if [[ -z "$COPILOT_SESSION_TOKEN" || "$COPILOT_SESSION_TOKEN" == "null" ]]; then
  echo "Error: Failed to get auth token." >&2
  exit 1
fi

readonly REQUEST_ID=$(uuidgen)

curl_args=(
  -sS -X POST
  --max-time 5
  "$API_ENDPOINT"
  -H "Content-Type: application/json"
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}"
  -H "Openai-Intent: conversation-panel"
  -H "X-Request-Id: $REQUEST_ID"
  -H "Vscode-Sessionid: some-session-id"
  -H "Vscode-Machineid: some-machine-id"
  -H "Copilot-Integration-Id: vscode-chat"
  -H "Editor-Plugin-Version: gptel/*"
  -H "Editor-Version: emacs/29.1"
  -d "$REQUEST_BODY"
)

if [[ "$VERBOSE" == "true" ]]; then
  curl_args+=(--verbose)
  json_args=$(printf '%s\n' "${curl_args[@]}" | jq -R . | jq -s .)

  echo "--- To re-run command, copy and paste below ---" >&2
  jq -r "@sh" <<< "$json_args" >&2
  echo "----------------------------------------------" >&2
fi

if [[ -n "$STATUS_FILE" ]]; then
  curl_args+=(--write-out "$(printf '%%output{%s}
{
  "http_code": %%{http_code},
  "exitcode": %%{exitcode},
  "errormsg": "%%{errormsg}"
}' "$STATUS_FILE")")
fi

log_debug "running curl with args ${curl_args[@]}"

curl "${curl_args[@]}"
