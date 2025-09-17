# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.bash
set -euo pipefail
#set -x

# --- Setup ---
echo "🧪 Running test for sse_completion_response.bash..."
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"

register_dep sse_generator "test/mocks/server/copilot/sse_completion_response.bash"

readonly EXPECTED_OUTPUT_FILE=$(resolve_path "test/mocks/sse-response.txt")
readonly MESSAGE_PARTS='["Hello", "!", " How", " can", " I", " assist", " you", " today", "?"]'
readonly PROMPT_TOKENS=7
readonly CREATED_TS=1757366620
readonly ID="chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"

if [ ! -f "$EXPECTED_OUTPUT_FILE" ]; then
    echo "Error: Expected output file not found at '$EXPECTED_OUTPUT_FILE'." >&2
    exit 1
fi

echo "▶️  Running test..."

# --- Test Execution ---
# Run diff only once, capturing its output and exit code.

# Temporarily disable "exit on error" to handle diff's non-zero exit code.
set +e
DIFF_OUTPUT=$(exec_dep sse_generator \
    --message-parts "$MESSAGE_PARTS" \
    --prompt-tokens "$PROMPT_TOKENS" \
    --created "$CREATED_TS" \
    --id "$ID" | diff --side-by-side - "$EXPECTED_OUTPUT_FILE")
diff_exit_code=$?
set -e

# --- Verification ---
# Check the captured exit code to determine pass or fail.
if [ "$diff_exit_code" -eq 0 ]; then
    echo "✅ SUCCESS: The generated output exactly matches the expected response."
    exit 0
else
    echo "❌ FAILURE: The generated output does not match the expected response."
    echo ""
    echo "--- Diff (what changed) ---"
    # Print the captured diff output.
    echo "$DIFF_OUTPUT"
    exit 1
fi
