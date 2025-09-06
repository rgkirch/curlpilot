#!/bin/env bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$0")

# Define file paths relative to the script's directory
CONFIG_DIR="$HOME/.config/curlpilot"
TOKEN_FILE="$CONFIG_DIR/token.txt"
LOGIN_SCRIPT="$SCRIPT_DIR/login.sh"

# Default stream setting
STREAM_ENABLED=true

# Function to display usage information
usage() {
  echo "Usage: echo \"your prompt\" | $0 [--stream=true|false] [--help]"
  echo ""
  echo "Options:"
  echo "  --stream=true|false  Enable or disable streaming responses. Default is true."
  echo "  --help               Display this help message."
  exit 0
}

# Parse arguments
for arg in "$@"; do
  case $arg in
    --stream=true)
      STREAM_ENABLED=true
      shift # Remove argument from processing
      ;;
    --stream=false)
      STREAM_ENABLED=false
      shift # Remove argument from processing
      ;;
    --stream=*)
      echo "Error: Invalid value for --stream. Use --stream=true or --stream=false." >&2
      exit 1
      ;;
    --help)
      usage
      ;;
    *)
      # Unknown argument, keep it for later processing if any
      ;;
  esac
done


# Function to read token and check expiration
read_and_check_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "Error: Token file not found. Please run $LOGIN_SCRIPT first." >&2
    exit 1
  fi

  source "$TOKEN_FILE" # Load COPILOT_SESSION_TOKEN and EXPIRES_AT

  if [[ -z "${COPILOT_SESSION_TOKEN-}" || -z "${EXPIRES_AT-}" ]]; then
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

# Get user prompt from stdin
if [ -t 0 ]; then
    echo "Error: This script expects input via stdin. Example: echo \"your prompt\" | $0" >&2
    exit 1
fi
PROMPT=$(cat)


# Generate UUID
REQUEST_ID=$(uuidgen)

echo "Sending request to Copilot..." >&2

# Set the dynamic part of the jq filter based on the stream setting.
if [ "$STREAM_ENABLED" = true ]; then
  JQ_FILTER_KEY="delta"
else
  JQ_FILTER_KEY="message"
fi

# --- Unified Pipeline ---
# This single pipeline builds the JSON payload, sends it to the API via curl,
# and processes the streaming or non-streaming response in one continuous flow.
echo "$PROMPT" |
  jq -Rs \
    --argjson stream_enabled "${STREAM_ENABLED}" \
    '{
      "model": "gpt-4.1",
      "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": .}
      ],
      "stream": $stream_enabled
    }' |
  curl -fS -s -N -X POST \
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
    -d @- |
  grep -v '^data: \[DONE\]$' |
  sed 's/^data: //' |
  jq -j -n --arg key "$JQ_FILTER_KEY" \
    'inputs | try (.choices[0][$key].content? // empty)'

echo

