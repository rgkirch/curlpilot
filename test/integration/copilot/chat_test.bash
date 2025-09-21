# test/copilot/chat_integration_test.bash
set -uo pipefail
#set -x

# PURPOSE: Verify that chat.bash correctly processes input, sends a valid
# HTTP request, and correctly parses a dynamically generated streamed response.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for chat.bash with dynamic mock response..."

# --- Test Setup ---
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"
register_dep chat "copilot/chat.bash"
register_dep sse_generator "test/mocks/server/copilot/sse_completion_response.bash"

PORT=$(shuf -i 20000-65000 -n 1)
export MOCK_PORT=$PORT
export CPO_CONFIG_BASH="$(resolve_path "test/mocks/config.bash")"
export CPO_COPILOT__AUTH_BASH="$(resolve_path test/mocks/scripts/success/auth.bash)"

LOG_FILE="chat_request.log"
EXPECTED_OUTPUT="Why don't scientists trust atoms? Because they make up everything!"
MESSAGE_PARTS="[\"Why don't \",\"scientists \",\"trust atoms? \",\"Because they \",\"make up everything!\"]"
CREATED_TIMESTAMP=$(date +%s)
COMPLETION_ID="chatcmpl-test-${CREATED_TIMESTAMP}"

( (
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n"
    exec_dep sse_generator \
      --message_parts "$MESSAGE_PARTS" \
      --prompt_tokens 15 \
      --created "$CREATED_TIMESTAMP" \
      --id "$COMPLETION_ID"
  ) | nc -l "$PORT" > "$LOG_FILE" ) &
NC_PID=$!

trap 'kill "$NC_PID" 2>/dev/null || true; echo "--- Captured Request Log ---"; cat "$LOG_FILE" &>/dev/null && rm -f "$LOG_FILE";' EXIT
sleep 0.1

# --- Test Execution ---
CHAT_INPUT='[{"role":"user","content":"Tell me a joke"}]'
FINAL_OUTPUT=$(exec_dep chat --messages "$CHAT_INPUT")

wait "$NC_PID"

# --- Assertions ---
echo "Verifying captured HTTP request in '$LOG_FILE'..."

# (FIXED) Replaced silent greps with verbose assertion blocks
if ! grep -q "POST /chat/completions HTTP/1.1" "$LOG_FILE"; then
    echo "❌ Test failed: Request line not found in log."
    exit 1
fi

if ! grep -q "Host: localhost:$PORT" "$LOG_FILE"; then
    echo "❌ Test failed: Host header not found in log."
    exit 1
fi

if ! grep -q '"messages":\[{"role":"user","content":"Tell me a joke"}\]' "$LOG_FILE"; then
    echo "❌ Test failed: Request body content not found in log."
    exit 1
fi

echo "Verifying final output..."

if [[ "$FINAL_OUTPUT" != "$EXPECTED_OUTPUT" ]]; then
    echo "❌ Test failed: Unexpected final output."
    echo "Expected: '$EXPECTED_OUTPUT'"
    echo "Got:      '$FINAL_OUTPUT'"
    exit 1
fi

echo "✅ Integration test for chat.bash completed successfully."

exit 0
