# test/mock/server/server.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../deps.bash"
register_dep parse_args "parse_args/parse_args.bash"

readonly ARG_SPEC_JSON='{
  "port": {
    "type": "number",
    "description": "Required. The port number for the server to listen on."
  },
  "stream": {
    "type": "boolean",
    "default": true,
    "description": "If true, serve a streaming SSE response."
  },
  "message_content": {
    "type": "string",
    "default": "Hello from the mock server!",
    "description": "The string content for the mock response."
  }
}'



log "Script started."

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

log "Arguments parsed: '$PARSED_ARGS'"

if [[ $(jq --raw-output '.help_requested' <<< "$PARSED_ARGS") == "true" ]]; then
  exit 0
fi

readonly PORT=$(jq --raw-output '.port' <<< "$PARSED_ARGS")
readonly STREAM_ENABLED=$(jq --raw-output '.stream' <<< "$PARSED_ARGS")
readonly MESSAGE_CONTENT=$(jq --raw-output '.message_content' <<< "$PARSED_ARGS")

log "Generating streaming response."
response_file=$(mktemp)
log "response_file $response_file"
trap 'rm -f "$response_file"' EXIT

log "MESSAGE_CONTENT $MESSAGE_CONTENT"
{
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n"
  "$(path_relative_to_here "generate_content_response.bash")" --text "$MESSAGE_CONTENT"
} > "$response_file"
log "Streaming response file created: $response_file"

log "Starting socat server on port $PORT."

REQUEST_LOG_FILE="$BATS_TEST_TMPDIR/request.log"
log "Request log will be at: $REQUEST_LOG_FILE"
HANDLER_SCRIPT="$(path_relative_to_here "handle_request.sh")"

socat -T30 TCP4-LISTEN:"$PORT",reuseaddr EXEC:"bash '$HANDLER_SCRIPT' '$REQUEST_LOG_FILE' '$response_file'"

log "socat server finished."
