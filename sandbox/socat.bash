#!/usr/bin/env bash

set -euo pipefail

# Create a temporary directory for our scripts and logs
DEMO_DIR=$(mktemp -d)
trap 'echo "[MAIN] Cleaning up..."; rm -rf "$DEMO_DIR"' EXIT
cd "$DEMO_DIR"

echo "📂 Demo running in: $DEMO_DIR"
echo "---"

# 1. Create the handler script that socat will run.
#    This script's output will be captured in server.log.
cat > handler.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[HANDLER] ✅ Connection received, handler is now running."

# Read the first line of the HTTP request from stdin to prove we got it
read -r request_line
echo "[HANDLER] ➡️  Read from client: '$request_line'"

# Send a valid HTTP response back to the client via stdout.
# The blank line (\r\n\r\n) is crucial to separate headers from the body.
echo -e "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 13\r\n\r\nHello, socat!"

echo "[HANDLER] ⬅️  Sending response and exiting."
EOF

chmod +x handler.sh

# 2. Start the server
PORT=$(shuf -i 20000-65000 -n 1)
echo "[MAIN] 🚀 Starting single-shot socat server on port $PORT..."

# CORRECTED INVOCATION:
# - No 'fork': socat will handle ONE connection and then exit.
# - socat's stdio (-) is piped to our handler script.
# - The entire pipeline runs in the background.
{ socat TCP-LISTEN:"$PORT",reuseaddr - | ./handler.sh; } > server.log 2>&1 &
PIPELINE_PID=$!

# Give the server a moment to start listening
sleep 0.5
echo "[MAIN] PID of server pipeline is $PIPELINE_PID"
echo "---"

# 3. Run the client
echo "[MAIN] 📞 Sending request with curl..."
RESPONSE=$(curl --show-error --fail http://127.0.0.1:"$PORT"/test)
echo "[MAIN] 💻 Curl response: '$RESPONSE'"
echo "---"

# 4. Show the results
echo "[MAIN] Server should have exited automatically after one request."
wait "$PIPELINE_PID" 2>/dev/null || true # Wait for the background job to complete

echo "[MAIN] 📄 Server log (server.log) now shows the handler's output:"
echo "------------------------------------------------------------------"
cat server.log
echo "------------------------------------------------------------------"
