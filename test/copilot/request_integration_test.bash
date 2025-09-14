#!/bin/bash
set -euo pipefail

# PURPOSE: Verify the raw HTTP request sent by curl is correctly formatted.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for copilot/request.bash..."

# --- Test Setup ---
source "./deps.bash"

PORT=8080
LOG_FILE="request.log"

# 1. Start a netcat listener in the background to capture the request
nc -l "$PORT" > "$LOG_FILE" &
NC_PID=$!

# 2. Set a trap to ensure netcat is killed and the log is removed on exit
trap 'kill "$NC_PID"; rm -f "$LOG_FILE";' EXIT

# 3. Use the simple 'success' mock for the auth dependency
export CPO_COPILOT__AUTH_SH="./test/mocks/scripts/success/auth.bash"

# 4. Set environment, pointing the API to our local netcat listener
export API_ENDPOINT="http://localhost:$PORT"
export COPILOT_SESSION_TOKEN="integration-test-fake-token"


# --- Run the Test ---
# The script will hang here until netcat receives a request and closes the connection.
echo '{"prompt": "hello"}' | ./copilot/request.bash


# --- Verification ---
echo "Verifying captured HTTP request in '$LOG_FILE'..."

# Check that essential headers and the body exist in the raw request
grep -q "POST / HTTP/1.1" "$LOG_FILE"
grep -q "Host: localhost:$PORT" "$LOG_FILE"
grep -q "Authorization: Bearer integration-test-fake-token" "$LOG_FILE"
grep -q '{"prompt": "hello"}' "$LOG_FILE"

echo "✅ Integration test completed successfully."
