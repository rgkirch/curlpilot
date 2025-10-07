# src/server/handle_request.bash
#set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

# Arguments passed from socat EXEC
REQUEST_LOG_FILE="$1"
log_debug "REQUEST_LOG_FILE $REQUEST_LOG_FILE"
RESPONSE_FILE="$2"
log_debug "RESPONSE_FILE $RESPONSE_FILE"

# Ensure log file is empty for the new request
> "$REQUEST_LOG_FILE"

# Read headers line by line to find the Content-Length
content_length=0
while read -r line; do
  # Clean carriage returns
  line=$(echo "$line" | tr -d '\r')
  # Log the line
  echo "$line" >> "$REQUEST_LOG_FILE"
  # Extract Content-Length value
  if [[ "$line" =~ ^Content-Length:\ ([0-9]+) ]]; then
    content_length=${BASH_REMATCH[1]}
  fi
  # An empty line signifies the end of the headers
  if [[ -z "$line" ]]; then
    break
  fi
done

# If a Content-Length was found, read exactly that many bytes for the body
if [[ "$content_length" -gt 0 ]]; then
  head -c "$content_length" >> "$REQUEST_LOG_FILE"
fi

# Now that the full request is read and logged, send the response.
cat "$RESPONSE_FILE"
