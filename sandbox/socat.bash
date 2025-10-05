#!/usr/bin/env bash

set -euo pipefail

# Create a temporary directory for our scripts and logs
DEMO_DIR=$(mktemp -d)
trap 'echo "Cleaning up..."; rm -rf "$DEMO_DIR"' EXIT
cd "$DEMO_DIR"

echo "📂 Demo running in: $DEMO_DIR"
echo "---"

# 1. Create the handler script that socat will run.
#    This script will be executed ONLY when a connection is made.
cat > handler.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[HANDLER] ✅ Connection received, handler is now running."

# Read the first line of the HTTP request from stdin
read -r request_line
echo "[HANDLER] ➡️  Read from client: '$request_line'"

# Send a simple HTTP response back to the client via stdout
echo -e "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 13\r\n"
echo "[HANDLER] ⬅️  Sending response and exiting."
echo
echo "Hello, socat!"
EOF

chmod +x handler.sh

# 2. Start the server
#    - We'll pick a random free port.
#    - We launch socat in the background so our main script can continue.
PORT=$(shuf -i 20000-65000 -n 1)
echo "[MAIN] 🚀 Starting socat server on port $PORT..."

# The CORRECT invocation:
# socat listens on the port and pipes the connection to/from its stdin/stdout.
# The shell then pipes socat's stdio to our handler script.
socat TCP-LISTEN:"$PORT",reuseaddr,fork - > server.log 2>&1 &
SOCAT_PID=$!

# Give the server a moment to start listening
sleep 0.5
echo "[MAIN] PID of socat listener is $SOCAT_PID"
echo "---"

# 3. Run the client
#    Now we'll connect with curl. Socat will accept the connection and
#    finally execute the handler script.
echo "[MAIN] 📞 Sending request with curl..."
curl --silent http://127.0.0.1:"$PORT"/test

echo
echo "---"
echo "[MAIN] ✅ Request finished."

# 4. Clean up and show the results
kill "$SOCAT_PID"
wait "$SOCAT_PID" 2>/dev/null || true # wait for it to exit, ignore error if already gone

echo "[MAIN] 📄 Server log (server.log) shows the handler only ran AFTER the connection:"
echo "------------------------------------------------------------------"
cat server.log
echo "------------------------------------------------------------------"
