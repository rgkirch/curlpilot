# test/copilot/request_integration_test.bash
set -euox pipefail

# PURPOSE: Verify the raw HTTP request sent by curl is correctly formatted
# and that the response from the server is correctly returned.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for copilot/request.bash..."

# --- Test Setup ---
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../deps.bash"
register_dep request copilot/request.bash

PORT=8080
LOG_FILE="request.log"
MOCK_RESPONSE_FILE=$(resolve_path "test/mocks/server/copilot/mock_http_response.txt")

# Create temp files for the results
BODY_FILE=$(mktemp)
STATUS_FILE=$(mktemp)
EXIT_CODE_FILE=$(mktemp)

# 1. Start a netcat listener in the background to capture the request and send a mock response
(cat "$MOCK_RESPONSE_FILE" | nc -l "$PORT" > "$LOG_FILE") &
NC_PID=$!

# 2. Set a trap to ensure netcat is killed and the log is removed on exit
trap 'echo "--- Captured Request Log ---"; cat "$LOG_FILE"; rm -f "$LOG_FILE" "$BODY_FILE" "$STATUS_FILE" "$EXIT_CODE_FILE";' EXIT

# 3. Use the simple 'success' mock for the auth dependency
export CPO_COPILOT__AUTH_BASH="./test/mocks/scripts/success/auth.bash"
export CPO_COPILOT__CONFIG_BASH="./test/mocks/scripts/success/config.bash"

# 4. Set environment, pointing the API to our local netcat listener
export API_ENDPOINT="http://localhost:$PORT"
export COPILOT_SESSION_TOKEN="integration-test-fake-token"


# --- Run the Test ---
# The script will hang here until netcat receives a request and closes the connection.
# The response from request.bash is piped to a subshell that saves the parts to temp files.
set +e
echo '{"prompt": "hello"}' | exec_dep request | {
    IFS= read -r -d $'' body
    read -r status || [[ -n "$body" ]]
    echo "$body" > "$BODY_FILE"
    echo "$status" > "$STATUS_FILE"
    echo "${PIPESTATUS[0]}" > "$EXIT_CODE_FILE"
}
set -e

# Read back the results
RESPONSE_BODY=$(cat "$BODY_FILE")
RESPONSE_STATUS=$(cat "$STATUS_FILE")
CURL_EXIT_CODE=$(cat "$EXIT_CODE_FILE")

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
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

echo "Verifying response from request..."
EXPECTED_RESPONSE_BODY='{"message": "test response"}'
if [ "$RESPONSE_BODY" != "$EXPECTED_RESPONSE_BODY" ]; then
    echo "Test failed: Unexpected response body."
    echo "Expected: $EXPECTED_RESPONSE_BODY"
    echo "Got: $RESPONSE_BODY"
    exit 1
fi

# Verify the status JSON
if ! echo "$RESPONSE_STATUS" | jq -e '.http_code == 200 and .exitcode == 0' > /dev/null; then
    echo "Test failed: Unexpected status object."
    echo "Got: $RESPONSE_STATUS"
    exit 1
fi

echo "✅ Integration test completed successfully."
