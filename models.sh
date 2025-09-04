#!/bin/bash

CONFIG_DIR="$HOME/.config/curlpilot"
TOKEN_FILE="$CONFIG_DIR/token.txt"
source "$TOKEN_FILE"

curl -fS -s https://api.githubcopilot.com/models \
  -H "Content-Type: application/json" \
  -H "Copilot-Integration-Id: vscode-chat" \
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}" | jq -r '.data[].id'
