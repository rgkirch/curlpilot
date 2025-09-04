#!/bin/bash
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$0")

# Define file paths relative to the script's directory
CONFIG_DIR="$HOME/.config/curlpilot"
TOKEN_FILE="$CONFIG_DIR/token.txt"
LOGIN_SCRIPT="$SCRIPT_DIR/login.sh"

# Function to read token and check expiration
read_and_check_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "Error: Token file not found. Please run $LOGIN_SCRIPT first." >&2
    exit 1
  fi

  source "$TOKEN_FILE" # Load COPILOT_SESSION_TOKEN and EXPIRES_AT

  if [[ -z "${COPILOT_SESSION_TOKEN}" || -z "${EXPIRES_AT}" ]]; then
    echo "Error: Token file is incomplete or malformed. Please run $LOGIN_SCRIPT again." >&2
    exit 1
  fi

  current_time=$(date +%s)
  # Add a 60-second buffer to be safe
  if (( current_time > (EXPIRES_AT - 60) )); then
    echo "Copilot token has expired or is about to. Attempting to refresh..." >&2
    if "$LOGIN_SCRIPT"; then # Call login.sh to refresh token
      source "$TOKEN_FILE" # Reload new token
      echo "Token refreshed successfully." >&2
    else
      echo "Failed to refresh token. Please run $LOGIN_SCRIPT manually." >&2
      exit 1
    fi
  fi
}

# Read and check token
read_and_check_token

# Get user prompt
PROMPT_ARGS="$*" # Capture all arguments first
PROMPT_PIPE=""

if [[ -p /dev/stdin ]]; then
  PROMPT_PIPE=$(cat)
fi

# Combine arguments and piped input
if [[ -n "$PROMPT_ARGS" && -n "$PROMPT_PIPE" ]]; then
  PROMPT="${PROMPT_ARGS}\n${PROMPT_PIPE}"
elif [[ -n "$PROMPT_ARGS" ]]; then
  PROMPT="$PROMPT_ARGS"
elif [[ -n "$PROMPT_PIPE" ]]; then
  PROMPT="$PROMPT_PIPE"
else
  echo "Usage: $0 <your_prompt>"
  echo "Or pipe input: echo \"Your prompt\" | $0"
  exit 1
fi


# Generate UUID
REQUEST_ID=$(uuidgen)

# --- MODIFICATION 1: Build JSON payload safely with jq ---
JSON_PAYLOAD=$(jq -n \
  --arg prompt "$PROMPT" \
  '{
    "model": "gpt-4.1",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": $prompt}
    ],
    "stream": true
  }')

echo "Sending request to Copilot..." >&2

# Execute curl and process streaming response
curl -s -N -X POST \
  https://api.githubcopilot.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}" \
  -H "Openai-Intent: conversation-panel" \
  -H "X-Request-Id: ${REQUEST_ID}" \
  -H "Vscode-Sessionid: some-session-id" \
  -H "Vscode-Machineid: some-machine-id" \
  -H "Copilot-Integration-Id: vscode-chat" \
  -H "Editor-Plugin-Version: gptel/*" \
  -H "Editor-Version: emacs/29.1" \
  -d "$JSON_PAYLOAD" | \
# --- MODIFICATION 2: Parse streaming response robustly with jq ---
while IFS= read -r line; do
  # Check for the end-of-stream signal
  if [[ "$line" == "data: [DONE]" ]]; then
    break
  fi

  # Process only data lines
  if [[ "$line" == "data: "* ]]; then
    # Remove "data: " prefix
    json_data="${line#data: }"

    # Safely parse the content from the JSON chunk using jq.
    # The filter '.choices[0].delta.content // ""' gets the content string.
    # If the content field is missing or null, it defaults to an empty string.
    content=$(echo "$json_data" | jq -r '.choices[0].delta.content // ""')

    # Print the content without a trailing newline
    printf "%s" "$content"
  fi
done

# Add a final newline at the very end for clean terminal output
echo
