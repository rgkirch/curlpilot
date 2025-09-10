#!/usr/bin/env bash

set -euo pipefail

source deps.sh
register auth "copilot/auth.sh"
register parse_args "copilot/parse_chat_args.sh"
source_dep auth

read_and_check_token

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
