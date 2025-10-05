#!/usr/bin/env bash

set -euo pipefail

# Create a temporary directory for our scripts and logs
DEMO_DIR=$(mktemp -d)
trap 'echo "[MAIN] Cleaning up..."; rm -rf "$DEMO_DIR"' EXIT
cd "$DEMO_DIR"

echo "📂 Demo running in: $DEMO_DIR"
echo "---"

# 1. Create the handler script.
cat > handler.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# socat makes the parent PID available in this environment variable.
echo "[HANDLER] ✅ Connection received. Parent socat listener PID is $SOCAT_PPID."

# Read the request from stdin
read -r request_line
echo "[HANDLER] ➡️  Read from client: '$request_line'"

# Send a valid HTTP response back to the client via stdout
echo -e "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 21\r\n\r\nHello from the handler!"

echo "[HANDLER] ⬅️  Response sent. Now terminating the parent listener..."

# This is the key: after handling the one request, we kill the parent.
# This allows the user's main script's `for` loop to continue.
kill "$SOCAT_PPID"
EOF

chmod +x handler.sh

# 2. Start the server
PORT=$(shuf -i 20000-65000 -n 1)
echo "[MAIN] 🚀 Starting socat server on port $PORT..."

# THE WORKING INVOCATION:
# - 'fork': Waits for a connection before running EXEC in a child process.
# - The handler script will kill the parent socat process when it's done.
socat TCP-LISTEN:"$PORT",reuseaddr,fork EXEC:./handler.sh > server.log 2>&1 &
SOCAT_PID=$!

sleep 0.5
echo "[MAIN] PID of main socat listener is $SOCAT_PID"
echo "---"

# 3. Run the client
echo "[MAIN] 📞 Sending request with curl..."
RESPONSE=$(curl --show-error --fail http://127.0.0.1:"$PORT"/test)
echo "[MAIN] 💻 Curl response: '$RESPONSE'"
echo "---"

# 4. Show the results
echo "[MAIN] The handler should have killed the server. Waiting for it to exit..."
wait "$SOCAT_PID" 2>/dev/null || true # Wait for the background job to complete

echo "[MAIN] 📄 Server log (server.log):"
echo "------------------------------------------------------------------"
cat server.log
echo "------------------------------------------------------------------"
