# test/mock/server/server.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"
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



log_debug "Script started."

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

log_debug "Arguments parsed: '$PARSED_ARGS'"

if [[ $(jq --raw-output '.help_requested' <<< "$PARSED_ARGS") == "true" ]]; then
  exit 0
fi

readonly PORT=$(jq --raw-output '.port' <<< "$PARSED_ARGS")
readonly STREAM_ENABLED=$(jq --raw-output '.stream' <<< "$PARSED_ARGS")
readonly MESSAGE_CONTENT=$(jq --raw-output '.message_content' <<< "$PARSED_ARGS")

log_debug "STREAM_ENABLED: $STREAM_ENABLED"

if [[ "$STREAM_ENABLED" == "false" ]]; then
  log_debug "Generating non-streaming response."
  body_file=$(mktemp)
  trap 'rm -f "$body_file"' EXIT
  "$(path_relative_to_here "completion_response.bash")" --message-content "$MESSAGE_CONTENT" > "$body_file"
  content_length=$(wc -c < "$body_file")
  response_file=$(mktemp)
  trap 'rm -f "$body_file" "$response_file"' EXIT
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: $content_length\r\n"
    cat "$body_file"
  } > "$response_file"
  log_debug "Non-streaming response file created: $response_file"
else
  log_debug "Generating streaming response."
  response_file=$(mktemp)
  log_debug "response_file $response_file"
  trap 'rm -f "$response_file"' EXIT
  message_parts_json=$(jq --compact-output --raw-input '
    split(" ")
    | . as $words
    | [
        range(0; $words | length)
        | if . < ($words | length) - 1 then $words[.] + " " else $words[.] end
      ]
  ' <<< "$MESSAGE_CONTENT")
  log_debug "message parts $message_parts_json"
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
    "$(path_relative_to_here "sse_completion_response.bash")" --message-parts "$message_parts_json"
  } > "$response_file"
  log_debug "Streaming response file created: $response_file"
fi

log_debug "Starting socat server on port $PORT."

REQUEST_LOG_FILE="$BATS_TEST_TMPDIR/request.log"
log_debug "Request log will be at: $REQUEST_LOG_FILE"
HANDLER_SCRIPT="$(path_relative_to_here "../handle_request.bash")"

socat -T30 TCP4-LISTEN:"$PORT",reuseaddr EXEC:"bash '$HANDLER_SCRIPT' '$REQUEST_LOG_FILE' '$response_file'"

log_debug "socat server finished."
