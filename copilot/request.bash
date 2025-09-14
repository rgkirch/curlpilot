#!/bin/bash
set -euo pipefail

# This script makes the final authenticated request to the Copilot API.

source "$(dirname "$0")/../deps.sh"

# Register dependencies for configuration and authentication.
register config "copilot/config.sh"
register auth "copilot/auth.sh"


# --- Get Configuration ---
CONFIG_JSON=$(exec_dep config)
API_ENDPOINT=$(echo "$CONFIG_JSON" | jq --raw-output '.api_endpoint')

# Validate that we received an endpoint
if [[ -z "$API_ENDPOINT" || "$API_ENDPOINT" == "null" ]]; then
  echo "Error: Failed to get API endpoint from config." >&2
  exit 1
fi


# --- Get Authentication Token ---
AUTH_JSON=$(exec_dep auth)
COPILOT_SESSION_TOKEN=$(echo "$AUTH_JSON" | jq --raw-output '.session_token')

# Validate that we received a token
if [[ -z "$COPILOT_SESSION_TOKEN" || "$COPILOT_SESSION_TOKEN" == "null" ]]; then
  echo "Error: Failed to get auth token." >&2
  exit 1
fi


# --- Execute API Request ---
curl -sS -N -X POST \
  "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${COPILOT_SESSION_TOKEN}" \
  -H "Openai-Intent: conversation-panel" \
  -H "X-Request-Id: $(uuidgen)" \
  -H "Vscode-Sessionid: some-session-id" \
  -H "Vscode-Machineid: some-machine-id" \
  -H "Copilot-Integration-Id: vscode-chat" \
  -H "Editor-Plugin-Version: gptel/*" \
  -H "Editor-Version: emacs/29.1" \
  -d @- \
  --write-out '\0
{
    "http_code": %{http_code},
    "exitcode": %{exitcode},
    "errormsg": "%{errormsg}"
}'
