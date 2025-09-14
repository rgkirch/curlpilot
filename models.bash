#!/bin/bash

set -euo pipefail

# curlpilot/models.sh

bash "$(dirname "$0")/login.sh"

CONFIG_DIR="$HOME/.config/curlpilot"
TOKEN_FILE="$CONFIG_DIR/token.txt"

if [[ ! -s "$TOKEN_FILE" ]]; then
  echo "Token file missing or empty!" >&2
  exit 1
fi

source "$TOKEN_FILE"

curl -fS -s https://api.githubcopilot.com/models \
  -H "Content-Type: application/json" \
  -H "Copilot-Integration-Id: vscode-chat" \
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}" | jq -r '.data[].id'

# gpt-4.1 - Use for tasks requiring maximum intelligence, complex reasoning, and state-of-the-art performance.
# gpt-4o - The best all-around model for a balance of high performance, speed, and cost, especially for multimodal (text, image, audio) applications.
# gpt-4o-mini - For fast, high-volume, and cost-sensitive tasks. It's the modern replacement for gpt-3.5-turbo.
# text-embedding-3-small - Used specifically for converting text into numerical vectors for tasks like semantic search and Retrieval-Augmented Generation (RAG).
