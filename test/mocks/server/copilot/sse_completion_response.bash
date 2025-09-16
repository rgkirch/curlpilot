# curlpilot/test/mocks/server/copilot/sse_completion_response.bash
set -euo pipefail

# This script reads a JSON object from stdin and generates a Server-Sent Events (SSE) stream
# to stdout using a predefined jq filter script.
#
# It is designed to be used in a pipeline.
#
# Example Usage:
#   echo '{"message_parts": ["Hello", " world!"], "prompt_tokens": 5}' | ./generate_sse.bash

# For robustness, use $HOME which reliably expands to the user's home directory.
JQ_SCRIPT_PATH="$HOME/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/test/mocks/server/copilot/sse_completion_response.jq"

# --- Script Body ---

# Check if the required jq script exists before proceeding.
if [ ! -f "$JQ_SCRIPT_PATH" ]; then
    # Print errors to stderr
    echo "Error: JQ script not found at the expected path:" >&2
    echo "$JQ_SCRIPT_PATH" >&2
    exit 1
fi

# Execute jq with the specified filter.
# -c for compact output, -r for raw string output (removes quotes).
# jq automatically reads from stdin if no input file is given.
jq -c -r -f "$JQ_SCRIPT_PATH"
