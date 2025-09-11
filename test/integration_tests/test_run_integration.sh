#!/bin/bash

# Test runner for curlpilot.sh

# curlpilot/test/integration_tests/test_run_integration.sh

set -euo pipefail

# --- Test Setup ---

# Get the directory of the test script itself
TEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define paths relative to the test script
CURLPILOT_SCRIPT="$TEST_DIR/../../curlpilot.sh"
# Generate a unique ID for this test run
export TEST_RUN_ID=$(uuidgen)

# Set the CHAT_SCRIPT environment variable to our mock server
export CHAT_SCRIPT="$TEST_DIR/../chat.sh"

# Create temporary directories for conversation history and log files
TEMP_CONFIG_DIR=$(mktemp -d)
export LOG_DIR=$(mktemp -d) # Export LOG_DIR
export LOG_FILE="$LOG_DIR/server_log.txt" # Export LOG_FILE

# Cleanup function to be called on exit
cleanup() {
    echo "Cleaning up..."
    rm -rf "$TEMP_CONFIG_DIR"
    rm -rf "$LOG_DIR" # Remove the log directory
}
trap cleanup EXIT

# Ensure the log file is clean before starting (not needed if LOG_DIR is new)
# rm -f "$LOG_FILE"


# --- Test Execution ---

echo "Running curlpilot.sh with two messages..."

# Simulate a user typing "message 1", pressing Ctrl+D, typing "message 2", and pressing Ctrl+D.
# The \x04 is the hex code for the EOT (End of Transmission) character, which is what Ctrl+D sends.
printf "message 1\x04message 2\x04" | "$CURLPILOT_SCRIPT" --config-dir="$TEMP_CONFIG_DIR"


# --- Assertions ---

echo "Verifying results..."

# 1. Check that the server was called twice for this specific test run
START_MARKER="--- PAYLOAD START $TEST_RUN_ID ---"
NUM_ENTRIES=$(grep -c -e "$START_MARKER" "$LOG_FILE")

if [ "$NUM_ENTRIES" -ne 2 ]; then
    echo "FAIL: Expected 2 payloads in the server log for this run, but found $NUM_ENTRIES."
    exit 1
fi
echo "OK: Server was called 2 times for this run."

# 2. Extract and check the content of the second payload
# This awk script finds the second block of text between the start and end markers for this run.
SECOND_PAYLOAD=$(awk -v marker="$START_MARKER" '$0 == marker {c++} c==2 { if ($0 != marker) print}' "$LOG_FILE" | sed -n '/$START_MARKER/d; /--- PAYLOAD END/q; p')

if [ -z "$SECOND_PAYLOAD" ]; then
    echo "FAIL: Could not extract the second payload from the log."
    exit 1
fi

MESSAGE_COUNT=$(echo "$SECOND_PAYLOAD" | jq 'length')

if [ "$MESSAGE_COUNT" -ne 3 ]; then
    echo "FAIL: Expected the second payload to contain 3 messages, but it contained $MESSAGE_COUNT."
    echo "Payload was: $SECOND_PAYLOAD"
    exit 1
fi
echo "OK: Second payload correctly contained 3 messages."

# 3. Check the content of the user messages
MSG1_CONTENT=$(echo "$SECOND_PAYLOAD" | jq -r '.[0].content')
MSG2_CONTENT=$(echo "$SECOND_PAYLOAD" | jq -r '.[2].content')

if [ "$MSG1_CONTENT" != "message 1" ]; then
    echo "FAIL: First message content was incorrect."
    exit 1
fi

if [ "$MSG2_CONTENT" != "message 2" ]; then
    echo "FAIL: Second message content was incorrect."
    exit 1
fi
echo "OK: Message content is correct."


# --- Test Success ---


