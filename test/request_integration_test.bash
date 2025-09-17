# test/copilot/request_integration_test.bash
set -uo pipefail
#set -x

# PURPOSE: Verify the raw HTTP request sent by curl is correctly formatted
# and that the response from the server is correctly returned.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for copilot/request.bash..."

# --- Test Setup ---
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"
register_dep request copilot/request.bash

PORT=$(shuf -i 20000-65000 -n 1)
LOG_FILE="request.log"
MOCK_RESPONSE_FILE=$(resolve_path "test/mocks/server/copilot/mock_http_response.txt")

# Create a temp directory for the results
TMP_DIR=$(mktemp -d)
BODY_FILE="$TMP_DIR/body"
STATUS_FILE="$TMP_DIR/status"
EXIT_CODE_FILE="$TMP_DIR/exit_code"

# 1. Start a netcat listener in the background to capture the request and send a mock response
(cat "$MOCK_RESPONSE_FILE" | nc -l "$PORT" > "$LOG_FILE") &
NC_PID=$!

# 2. Set a trap to ensure netcat is killed and the log is removed on exit
trap 'echo "--- Captured Request Log ---"; cat "$LOG_FILE"; rm -f "$LOG_FILE"; rm -rf "$TMP_DIR";' EXIT

# 3. Use the simple 'success' mock for the auth dependency
export CPO_COPILOT__AUTH_BASH="./test/mocks/scripts/success/auth.bash"
export CPO_COPILOT__CONFIG_BASH="./test/mocks/scripts/success/config.bash"

# 4. Set environment, pointing the API to our local netcat listener
export API_ENDPOINT="http://localhost:$PORT"
export COPILOT_SESSION_TOKEN="integration-test-fake-token"

exec_dep request --body '{"prompt":"hello"}' --status-file "$STATUS_FILE" > "$BODY_FILE"
CURL_EXIT_CODE=$?
RESPONSE_BODY=$(cat "$BODY_FILE")
RESPONSE_STATUS=$(cat "$STATUS_FILE")

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
    echo "Test failed with unexpected exit code: $CURL_EXIT_CODE"
    exit 1
fi

echo "Verifying captured HTTP request in '$LOG_FILE'..."

grep -q "POST / HTTP/1.1" "$LOG_FILE"
grep -q "Host: localhost:$PORT" "$LOG_FILE"
grep -q "Authorization: Bearer integration-test-fake-token" "$LOG_FILE"
grep -q '{"prompt":"hello"}' "$LOG_FILE"

echo "Verifying response from request..."
EXPECTED_RESPONSE_BODY='{"message": "test response"}'
if [ "$RESPONSE_BODY" != "$EXPECTED_RESPONSE_BODY" ]; then
    echo "Test failed: Unexpected response body."
    echo "Expected: $EXPECTED_RESPONSE_BODY"
    echo "Got: $RESPONSE_BODY"
    exit 1
fi

if ! echo "$RESPONSE_STATUS" | jq -e '.http_code == 200 and .exitcode == 0' > /dev/null; then
    echo "Test failed: Unexpected status object."
    echo "Got: $RESPONSE_STATUS"
    exit 1
fi

echo "✅ Integration test completed successfully."
