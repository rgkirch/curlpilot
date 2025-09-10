#!/bin/bash

set -euo pipefail

# Mock chat.sh for testing purposes.
# It records the payload it receives and returns a canned response.

# Get the directory where the script itself is located.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/server_log.txt}"

# Use markers with the unique test run ID to clearly separate payloads.
# The TEST_RUN_ID is inherited from the environment set by the test runner.
echo "--- PAYLOAD START ${TEST_RUN_ID} ---" >> "$LOG_FILE"

# Append stdin to the server log
cat >> "$LOG_FILE"

echo "--- PAYLOAD END ${TEST_RUN_ID} ---" >> "$LOG_FILE"

# Return a canned response for curlpilot.sh to continue
echo "OK"
