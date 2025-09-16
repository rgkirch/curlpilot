# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.bash
set -euo pipefail

# This script tests the SSE generator script by feeding it command-line arguments
# and comparing its output against a known-good "golden" file.

# --- Setup ---
echo "🧪 Running test for sse_completion_response.bash..."
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../../deps.bash"

register_dep sse_generator "test/mocks/server/copilot/sse_completion_response.bash"

readonly EXPECTED_OUTPUT_FILE=$(resolve_path "test/mocks/sse-response.txt")

# Define the arguments that will be passed to the generator script.
readonly MESSAGE_PARTS='["Hello", "!", " How", " can", " I", " assist", " you", " today", "?"]'
readonly PROMPT_TOKENS=7
readonly CREATED_TS=1757366620
readonly ID="chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"

if [ ! -f "$EXPECTED_OUTPUT_FILE" ]; then
    echo "Error: Expected output file not found at '$EXPECTED_OUTPUT_FILE'." >&2
    exit 1
fi

echo "▶️  Running test..."

ACTUAL_OUTPUT=$(exec_dep sse_generator \
    --message-parts "$MESSAGE_PARTS" \
    --prompt-tokens "$PROMPT_TOKENS" \
    --created "$CREATED_TS" \
    --id "$ID")

if diff --brief <(echo -n "$ACTUAL_OUTPUT") "$EXPECTED_OUTPUT_FILE" >/dev/null; then
    echo "✅ SUCCESS: The generated output exactly matches the expected response."
    exit 0
else
    echo "❌ FAILURE: The generated output does not match the expected response."
    echo ""
    echo "--- Diff (what changed) ---"
    # Run diff again, this time with a unified format to show the user what's wrong.
    diff --unified <(echo -n "$ACTUAL_OUTPUT") "$EXPECTED_OUTPUT_FILE"
    exit 1
fi
