# test/mock/server/copilot.bash
set -euo pipefail
set -x

# This is the core synchronous server. It prepares and serves one
# response, blocking until the connection is complete.

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

readonly ARG_SPEC_JSON='{
  "stream": { "type": "boolean", "default": true },
  "message_content": { "type": "string", "default": "Hello from the mock server!" }
}'

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

readonly STREAM_ENABLED=$(jq --raw-output '.stream' <<< "$PARSED_ARGS")
readonly MESSAGE_CONTENT=$(jq --raw-output '.message_content' <<< "$PARSED_ARGS")

PORT=$(shuf -i 20000-65000 -n 1)

# Echo the port to stdout so the process that launched it knows where to connect.
echo "$PORT"

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

if [[ "$STREAM_ENABLED" == "true" ]]; then
  message_parts_json=$(jq -cR 'split(" ")' <<< "$MESSAGE_CONTENT")
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
    "$(path_relative_to_here "copilot/sse_completion_response.bash")" --message-parts "$message_parts_json"
  } > "$response_file"
else
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n"
    "$(path_relative_to_here "copilot/completion_response.bash")" --message-content "$MESSAGE_CONTENT"
  } > "$response_file"
fi

# Run nc in the foreground. This script will now block until a client connects.
nc -l "$PORT" --send-only < "$response_file"
