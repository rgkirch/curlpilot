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

source deps.sh
register auth "copilot/auth.sh"
register parse_args "copilot/parse_chat_args.sh"
source_dep auth

read_and_check_token # auth

# This command captures both the response body and the HTTP status code.
# The status code is appended to the output on a new line, thanks to -w "\n%{http_code}".
# The -f flag is removed to ensure we receive the body even on error.
#
# The -s flag in jq stands for --slurp. It changes how jq reads its input.
# Instead of processing each JSON object from the input stream one at a time,
# the -s flag tells jq to read the entire stream of objects into a single large
# array. It then runs your filter just once on that complete array.
#
# echo '{"role": "user", "content": "hi"}' | ./copilot/chat.sh
# Sending request to Copilot...

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
