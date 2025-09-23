# test/mock/server/copilot.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

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

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

if [[ $(jq --raw-output '.help_requested' <<< "$PARSED_ARGS") == "true" ]]; then
  exit 0
fi

readonly PORT=$(jq --raw-output '.port' <<< "$PARSED_ARGS")
readonly STREAM_ENABLED=$(jq --raw-output '.stream' <<< "$PARSED_ARGS")
readonly MESSAGE_CONTENT=$(jq --raw-output '.message_content' <<< "$PARSED_ARGS")

if [[ "$STREAM_ENABLED" == "false" ]]; then
  body_file=$(mktemp)
  trap 'rm -f "$body_file"' EXIT
  "$(path_relative_to_here "copilot/completion_response.bash")" --message-content "$MESSAGE_CONTENT" > "$body_file"
  content_length=$(wc -c < "$body_file")
  response_file=$(mktemp)
  trap 'rm -f "$body_file" "$response_file"' EXIT
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: $content_length\r\n"
    cat "$body_file"
  } > "$response_file"
else
  response_file=$(mktemp)
  trap 'rm -f "$response_file"' EXIT
  message_parts_json=$(jq --compact-output --raw-input 'split(" ")' <<< "$MESSAGE_CONTENT")
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
    "$(path_relative_to_here "copilot/sse_completion_response.bash")" --message-parts "$message_parts_json"
  } > "$response_file"
fi

echo "nc is listening on PORT $PORT" >> "err.log"

nc --listen "$PORT" --send-only < "$response_file"

echo "nc is done" >> "err.log"
