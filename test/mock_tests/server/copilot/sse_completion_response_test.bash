#!/bin/bash

set -euo pipefail

# curlpilot/test/mock_tests/server/copilot/sse_completion_response_test.sh

# This script tests the SSE generator script by feeding it a predefined
# JSON input and comparing its output against a known-good "golden" file.

# --- Configuration ---
# Use $HOME for robustness.
BASE_PATH="$HOME/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test"

# The script we want to test.
GENERATOR_SCRIPT="$HOME/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test/mock/server/copilot/sse_completion_response.sh"

# The file containing the expected, correct output.
EXPECTED_OUTPUT_FILE="$BASE_PATH/sse-response.txt"

# This JSON input is designed to produce an output that exactly matches
# the contents of the EXPECTED_OUTPUT_FILE.
# The 'created' and 'id' fields are now provided as input to the jq script
# to ensure the output is deterministic and repeatable.
TEST_INPUT_JSON='{
  "message_parts": ["Hello", "!", " How", " can", " I", " assist", " you", " today", "?"],
  "prompt_tokens": 7,
  "created": 1757366620,
  "id": "chatcmpl-CDdcq1c8DjPBjsa8MlM7oQS2Vx8L9"
}'


# --- Pre-flight Checks ---
if [ ! -x "$GENERATOR_SCRIPT" ]; then
    echo "Error: Generator script '$GENERATOR_SCRIPT' not found or not executable." >&2
    echo "Please ensure it's in the same directory and run 'chmod +x $GENERATOR_SCRIPT'." >&2
    exit 1
fi

if [ ! -f "$EXPECTED_OUTPUT_FILE" ]; then
    echo "Error: Expected output file not found at '$EXPECTED_OUTPUT_FILE'." >&2
    exit 1
fi

# --- Test Execution ---
echo "▶️  Running test..."

# Generate the actual output by piping the test JSON into our generator script.
ACTUAL_OUTPUT=$(echo "$TEST_INPUT_JSON" | bash "$GENERATOR_SCRIPT")

# The jq script should now produce a completely static output based on the input.
# We use the '-q' flag (short for '--brief') which is more portable than '--quiet'.
# It exits with 0 if files are the same, and 1 if they differ, suppressing output.
diff -q <(echo "$ACTUAL_OUTPUT") "$EXPECTED_OUTPUT_FILE"

# Check the exit code of the diff command. 0 means no differences were found.
if [ $? -eq 0 ]; then
    echo "✅ SUCCESS: The generated output exactly matches the expected response."
    exit 0
else
    echo "❌ FAILURE: The generated output does not match the expected response."
    echo ""
    echo "--- Diff (what changed) ---"
    # Run diff again, this time with a unified format to show the user what's wrong.
    diff --unified <(echo "$ACTUAL_OUTPUT") "$EXPECTED_OUTPUT_FILE"
    exit 1
fi
