# test/copilot/chat_integration_test.bash
set -uo pipefail
#set -x

# PURPOSE: Verify that chat.bash correctly processes input, sends a valid
# HTTP request, and correctly parses a dynamically generated streamed response.
# This test must be run from the project's root directory.

echo "🧪 Running integration test for chat.bash with dynamic mock response..."

# --- Test Setup ---
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"
# 1. (MODIFIED) Register all script dependencies, including mocks.
register_dep chat "copilot/chat.bash"
register_dep sse_generator "test/mocks/server/copilot/sse_completion_response.bash"

PORT=8080
LOG_FILE="chat_request.log"

EXPECTED_OUTPUT="Why don't scientists trust atoms? Because they make up everything!"
MESSAGE_PARTS="[\"Why don't \",\"scientists \",\"trust atoms? \",\"Because they \",\"make up everything!\"]"
CREATED_TIMESTAMP=$(date +%s)
COMPLETION_ID="chatcmpl-test-${CREATED_TIMESTAMP}"

# 2. (MODIFIED) Start nc listener, using exec_dep to run the generator script.
(exec_dep sse_generator \
  --message_parts "$MESSAGE_PARTS" \
  --prompt_tokens 15 \
  --created "$CREATED_TIMESTAMP" \
  --id "$COMPLETION_ID" \
| nc -l "$PORT" > "$LOG_FILE") &
NC_PID=$!

trap 'kill "$NC_PID" 2>/dev/null; echo "--- Captured Request Log ---"; cat "$LOG_FILE" && rm "$LOG_FILE";' EXIT
sleep 0.1

export CPO_COPILOT__CONFIG_BASH="$(resolve_path "test/mocks/config.bash")"
export CPO_COPILOT__AUTH_BASH="$(resolve_path test/mocks/scripts/success/auth.bash)"

# --- Test Execution ---
CHAT_INPUT='[{"role":"user","content":"Tell me a joke"}]'
FINAL_OUTPUT=$(echo "$CHAT_INPUT" | exec_dep chat)

# --- Assertions ---
echo "Verifying captured HTTP request in '$LOG_FILE'..."
grep -q "POST /chat/completions HTTP/1.1" "$LOG_FILE"
grep -q "Host: localhost:$PORT" "$LOG_FILE"
grep -q '"messages":\[{"role":"user","content":"Tell me a joke"}\]' "$LOG_FILE"

echo "Verifying final output..."
read -r -d '' EXPECTED_WITH_NEWLINE << EOM
${EXPECTED_OUTPUT}

EOM

if [[ "$FINAL_OUTPUT" != "$EXPECTED_WITH_NEWLINE" ]]; then
    echo "Test failed: Unexpected final output."
    echo "Expected: '$EXPECTED_OUTPUT'"
    echo "Got:      '$FINAL_OUTPUT'"
    exit 1
fi

echo "✅ Integration test for chat.bash completed successfully."
