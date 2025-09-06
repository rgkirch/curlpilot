#!/usr/bin/env bash

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
