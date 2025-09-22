# test/mock/server/copilot.bash
set -euo pipefail
set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

readonly ARG_SPEC_JSON='{
  "stream": {
    "type": "boolean",
    "description": "If true, serve a streaming SSE response.",
    "default": true
  },
  "message_content": {
    "type": "string",
    "description": "A string for the mock response.",
    "default": "Hello from the mock server!"
  }
}'

# Build the job ticket and execute the parser.
job_ticket_json=$(jq --null-input \
  --argjson spec "$ARG_SPEC_JSON" \
  '{spec: $spec, args: $ARGS.positional}' \
  --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

# Extract the final values from the parsed JSON into Bash variables.
readonly STREAM_ENABLED=$(jq --raw-output '.stream' <<< "$PARSED_ARGS")
readonly MESSAGE_CONTENT=$(jq --raw-output '.message_content' <<< "$PARSED_ARGS")


# --- Server Logic ---
PORT=$(shuf -i 20000-65000 -n 1)

# The server logic runs in a background process to handle one connection.
(
  response_file=$(mktemp)
  # Ensure the temporary file is cleaned up when the subshell exits.
  trap 'rm -f "$response_file"' EXIT

  # Generate the correct response (streaming or not) into the temp file.
  if [[ "$STREAM_ENABLED" == "true" ]]; then
    # For streaming, split the message into words and create a JSON array.
    message_parts_json=$(jq -cnR 'split(" ")' <<< "$MESSAGE_CONTENT")

    {
      echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
      # Call the SSE generator with the JSON array of message parts.
      "$(path_relative_to_here "copilot/sse_completion_response.bash")" --message-parts "$message_parts_json"
    } > "$response_file"
  else
    # For non-streaming, use the message content as is.
    {
      echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n"
      # Call the standard generator with the single message string.
      "$(path_relative_to_here "copilot/completion_response.bash")" --message-content "$MESSAGE_CONTENT"
    } > "$response_file"
  fi

  # Serve the pre-generated response from the file to avoid deadlocks.
  nc -l "$PORT" < "$response_file"

) 3>&- &
SERVER_PID=$!

# Output the port and PID for the controlling script.
echo "$PORT"
echo "$SERVER_PID"
