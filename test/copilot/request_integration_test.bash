#!/bin/bash
set -euo pipefail

# PURPOSE: Verify the raw HTTP request sent by curl is correctly formatted.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for copilot/request.bash..."

# --- Test Setup ---
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../deps.bash"
register_dep request copilot/request.bash

PORT=8080
LOG_FILE="request.log"

# 1. Start a netcat listener in the background to capture the request
nc -l "$PORT" > "$LOG_FILE" &
NC_PID=$!

# 2. Set a trap to ensure netcat is killed and the log is removed on exit
trap 'echo "--- Captured Request Log ---"; cat "$LOG_FILE"; rm -f "$LOG_FILE";' EXIT

# 3. Use the simple 'success' mock for the auth dependency
export CPO_COPILOT__AUTH_BASH="./test/mocks/scripts/success/auth.bash"
export CPO_COPILOT__CONFIG_BASH="./test/mocks/scripts/success/config.bash"

# 4. Set environment, pointing the API to our local netcat listener
export API_ENDPOINT="http://localhost:$PORT"
export COPILOT_SESSION_TOKEN="integration-test-fake-token"


# --- Run the Test ---
# The script will hang here until netcat receives a request and closes the connection.
set +e
echo '{"prompt": "hello"}' | exec_dep request
CURL_EXIT_CODE=$?
set -e

if [ "$CURL_EXIT_CODE" -ne 52 ] && [ "$CURL_EXIT_CODE" -ne 0 ]; then
    echo "Test failed with unexpected exit code: $CURL_EXIT_CODE"
    exit 1
fi


# --- Verification ---
echo "Verifying captured HTTP request in '$LOG_FILE'..."

# Check that essential headers and the body exist in the raw request
grep -q "POST / HTTP/1.1" "$LOG_FILE"
grep -q "Host: localhost:$PORT" "$LOG_FILE"
grep -q "Authorization: Bearer integration-test-fake-token" "$LOG_FILE"
grep -q '{"prompt": "hello"}' "$LOG_FILE"

echo "✅ Integration test completed successfully."
