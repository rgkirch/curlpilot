# test_chat.bash

set -euo pipefail

# --- Setup Test Environment ---
# Create a temporary directory for the test and all its files
TEST_DIR=$(mktemp -d)
# Ensure the temporary directory is cleaned up when the script exits
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

echo "🧪 Test environment created at: $TEST_DIR"


# --- Create Script Under Test and Dummy Dependencies ---

# 1. copilot/chat.bash (The script we are testing)
cat << 'EOF' > copilot/chat.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep request "copilot/request.bash"
register_dep parse_args "parse_args.bash"
register_dep parse_response "copilot/parse_response.bash"
register_dep config "config.bash"

readonly ARG_SPEC_JSON=$(echo "$(exec_dep config)" | jq '
{
  "model": {
    "type": "string",
    "description": "Specify the AI model to use.",
    "default": (.model // "gpt-4.1")
  },
  "api_endpoint": {
    "type": "string",
    "description": "Specify the API endpoint for the chat service.",
    "default": (.api_endpoint // "https://api.githubcopilot.com/chat/completions")
  },
  "stream": {
    "type": "boolean",
    "description": "Enable or disable streaming responses.",
    "default": (.stream_enabled // true)
  }
}
')

J="$(jq --null-input \
  --argjson spec "$ARG_SPEC_JSON" \
  '{"spec": $spec, "args": $ARGS.positional}' \
  --args -- "$@")"

PARAMS_JSON=$(exec_dep parse_args "$J")

jq --slurp \
  --argjson params "$PARAMS_JSON" \
  '($params | {model, stream_enabled: .stream}) + {messages: .[0]}' \
| exec_dep request --body - \
| exec_dep parse_response

echo
EOF

# 2. deps.bash (A simple dependency loader for the test)
cat << 'EOF' > deps.bash
DEPS_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
declare -A DEPS
register_dep() { DEPS["$1"]="$DEPS_DIR/$2"; }
exec_dep() { bash "${DEPS[$1]}" "${@:2}"; }
EOF

# 3. parse_args.bash (Dummy: just extracts the default values)
cat << 'EOF' > parse_args.bash
jq -r '.spec | map_values(.default)'
EOF

# 4. copilot/request.bash (Dummy: calls config to get the URL and uses curl)
cat << 'EOF' > copilot/request.bash
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"
register_dep config "config.bash"
API_ENDPOINT=$(exec_dep config | jq -r '.api_endpoint')
curl --silent --no-buffer --request POST --data-binary @- "$API_ENDPOINT"
EOF

# 5. copilot/parse_response.bash (Dummy: parses the mock SSE stream)
cat << 'EOF' > copilot/parse_response.bash
grep '^data:' \
| sed 's/^data: //' \
| jq -r 'if .choices then .choices[0].delta.content else "" end' \
| tr -d '\n'
EOF

# --- Create Mocks ---

# 1. Mock config.bash (STUB)
# This is the key: it overrides the real config and points to our mock server.
MOCK_PORT=8080
cat << EOF > config.bash
#!/usr/bin/env bash
# Mock config that returns a JSON object pointing to our local nc server.
echo '{"api_endpoint": "http://localhost:$MOCK_PORT"}'
EOF

# 2. Mock API Response File
# This is the content our nc server will return.
cat << 'EOF' > mock_response.txt
HTTP/1.1 200 OK
Content-Type: text/event-stream
Connection: close

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"This "}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"is a "}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"mocked "}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"response."}}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
EOF


# --- Run Test ---

echo "--- Starting Test: chat.bash with mock server ---"

# Start the mock nc server in the background, serving our response file.
# The server will accept one connection and then terminate.
nc -l "$MOCK_PORT" < mock_response.txt &
NC_PID=$!

# Ensure nc is killed when the script exits, just in case.
trap 'kill "$NC_PID" 2>/dev/null; rm -rf "$TEST_DIR"' EXIT

# Give the server a moment to start listening.
sleep 0.1

# Prepare the JSON input that chat.bash expects on stdin.
CHAT_INPUT='[{"role": "user", "content": "Hello"}]'

# Execute the script and capture its standard output.
ACTUAL_OUTPUT=$(echo "$CHAT_INPUT" | copilot/chat.bash)

# Wait for the nc process to finish.
wait "$NC_PID"

# Define the output we expect based on the content in mock_response.txt.
EXPECTED_OUTPUT="This is a mocked response."

# --- Assert Results ---
echo
echo "Expected: '$EXPECTED_OUTPUT'"
echo "Actual:   '$ACTUAL_OUTPUT'"
echo

if [[ "$ACTUAL_OUTPUT" == "$EXPECTED_OUTPUT" ]]; then
  echo "✅ Test PASSED"
  exit 0
else
  echo "❌ Test FAILED"
  exit 1
fi
