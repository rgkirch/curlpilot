#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Configuration ---
# Pick a port for the server to listen on.
# If this port is in use, change it to another value (e.g., 8081).
PORT=8080

# --- Setup Temporary Environment ---
# Create a temporary directory for our server files.
# The 'trap' command ensures this directory is cleaned up when the script exits.
SERVER_DIR=$(mktemp -d)
trap 'echo "[INFO] Cleaning up and shutting down."; rm -rf "$SERVER_DIR"' EXIT

# Create directories for canned responses and for logging requests.
RESPONSES_DIR="$SERVER_DIR/responses"
REQUESTS_DIR="$SERVER_DIR/requests"
mkdir -p "$RESPONSES_DIR" "$REQUESTS_DIR"

echo "[INFO] Server environment created in: $SERVER_DIR"

# --- Create Sample Response Files ---
# Create a few simple text files to act as our sequential HTTP responses.
cat > "$RESPONSES_DIR/01_hello.http" <<'EOF'
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close

Hello, world!
This is the first response.
EOF

cat > "$RESPONSES_DIR/02_status.http" <<'EOF'
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close

Status: All systems nominal.
This is the second response.
EOF

cat > "$RESPONSES_DIR/03_goodbye.http" <<'EOF'
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close

Goodbye!
This is the final response. The server will shut down after this.
EOF

# --- Main Server Loop ---
echo "[INFO] Starting server on http://localhost:$PORT"
echo "[INFO] The server will handle one request for each file in '$RESPONSES_DIR' and then exit."

# Get a sorted list of all response files.
mapfile -t response_files < <(find "$RESPONSES_DIR" -type f | sort)
request_count=0

# Loop through each response file. For each file, we start a new socat listener
# that will handle exactly one connection and then exit.
for response_file in "${response_files[@]}"; do
  # Define where to save the incoming request for this iteration.
  request_log_file="$REQUESTS_DIR/request_${request_count}.log"

  echo "[SERVER] Waiting for request #${request_count}..."

  # Create a temporary, dedicated handler script for this specific request.
  # This is the most robust way to pass complex logic to socat's SYSTEM address.
  handler_script_path="$SERVER_DIR/handler.sh"
  cat > "$handler_script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Read headers line-by-line from stdin until a blank line is found.
# This explicitly stops the read process and avoids the deadlock.
while IFS= read -r line; do
  line=\${line%\$'\r'} # Remove trailing carriage return
  echo "\$line" >> "$request_log_file"
  if [[ -z "\$line" ]]; then
    break # Exit loop after finding the blank line (end of headers)
  fi
done

# Now that the request is logged, send the response file to stdout.
cat "$response_file"
EOF

  chmod +x "$handler_script_path"

  # The 'shut-down' option ensures the connection is closed gracefully after the response.
  socat \
    TCP-LISTEN:"$PORT",reuseaddr,shut-down \
    "SYSTEM:$handler_script_path"

  echo "[SERVER] Handled request #${request_count}. Request saved to '$request_log_file'."
  # Increment the counter for the next log file name.
  request_count=$((request_count + 1))
done

echo "[INFO] All responses have been served."
