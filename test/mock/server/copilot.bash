# test/mock/server/copilot.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

# 1. Update the spec to accept 'json' for message-content.
readonly ARG_SPEC_JSON='{
  "stream": {
    "type": "boolean",
    "description": "If true, serve a streaming SSE response. If false, serve a single JSON object.",
    "default": true
  },
  "message_content": {
    "type": "json",
    "description": "A single string or a JSON array of strings for the mock response(s).",
    "default": "\"Hello from the mock copilot server!\""
  }
}'

# 2. Parse the server's arguments.
job_ticket_json=$(jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

readonly STREAM_ENABLED=$(echo "$PARSED_ARGS" | jq -r '.stream')
# Keep message_content as a JSON literal to check its type.
readonly MESSAGE_CONTENT_JSON=$(echo "$PARSED_ARGS" | jq '.message_content')
readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# 3. Process message_content into a standard Bash array.
messages_to_serve=()
if [[ $(jq 'type' <<< "$MESSAGE_CONTENT_JSON") == '"array"' ]]; then
  # If it's a JSON array, read each element into the Bash array.
  mapfile -t messages_to_serve < <(jq -r '.[]' <<< "$MESSAGE_CONTENT_JSON")
else
  # If it's a single JSON string, add it as the only element.
  messages_to_serve+=("$(jq -r '.' <<< "$MESSAGE_CONTENT_JSON")")
fi

# --- Start Server ---
PORT=$(shuf -i 20000-65000 -n 1)

# This function contains the logic for generating a single response.
generate_response() {
  local message="$1"
  local generator_script=""
  local generator_args=()

  if [[ "$STREAM_ENABLED" == "true" ]]; then
    generator_script="$SCRIPT_DIR/sse_completion_response.bash"
    read -r -a words <<< "$message"
    local message_parts_json
    message_parts_json=$(jq -n --compact-output '$ARGS.positional' --args -- "${words[@]}")
    generator_args+=("--message-parts" "$message_parts_json")
  else
    generator_script="$SCRIPT_DIR/completion_response.bash"
    generator_args+=("--message-content" "$message")
  fi

  if [[ "$STREAM_ENABLED" == "true" ]]; then
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
  else
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n"
  fi
  "$generator_script" "${generator_args[@]}"
}

# 4. Run the main server loop in the background. It will iterate through the
#    messages, serving one response per connection.
(
  for message in "${messages_to_serve[@]}"; do
    # 1. Generate the entire response into a temporary file first.
    response_file=$(mktemp)
    generate_response "$message" > "$response_file"

    # 2. Serve the static content of the file with nc. This avoids the deadlock.
    nc -l "$PORT" < "$response_file"

    # 3. Clean up the temporary file for this specific request.
    rm "$response_file"
  done
) 3>&- &
SERVER_PID=$!


# Output the port and PID for the test script to use for connection and cleanup.
echo "$PORT"
echo "$SERVER_PID"
