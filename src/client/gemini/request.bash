# copilot/request.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep auth "gemini/auth.bash"
register_dep parse_args "parse_args/parse_args.bash"
register_dep config "config.bash"

readonly ARG_SPEC_JSON='{
  "body": {
    "type": "json",
    "description": "The JSON request body."
  },
  "api_endpoint": {
    "type": "string",
    "description": "The API endpoint to send the request to."
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
readonly API_ENDPOINT=$(echo "$PARSED_ARGS" | jq --raw-output '.api_endpoint')



curl_args=(
  -sS -X POST
  --max-time 5
  "$API_ENDPOINT"
  -H "Content-Type: application/json"
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
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

log_debug "running curl with args ${curl_args[@]}"

curl "${curl_args[@]}"
