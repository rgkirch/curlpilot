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
mkdir -p "$CONFIG_DIR"
GITHUB_PAT_FILE="$CONFIG_DIR/github_pat.txt"
TOKEN_FILE="$CONFIG_DIR/token.txt"

# Function to get Copilot session token using GitHub PAT
get_copilot_session_token() {
  local github_pat="$1"
  copilot_token_response=$(curl -fS -s -X GET \
    https://api.github.com/copilot_internal/v2/token \
    -H "Authorization: token $github_pat" \
    -H "Editor-Plugin-Version: gptel/*" \
    -H "Editor-Version: emacs/29.1")

  copilot_session_token=$(echo "$copilot_token_response" | jq -r '.token' || true)
  expires_at=$(echo "$copilot_token_response" | jq -r '.expires_at' || true)

  if [[ -n "$copilot_session_token" && -n "$expires_at" ]]; then
    echo "COPILOT_SESSION_TOKEN='$copilot_session_token'" > "$TOKEN_FILE"
    echo "EXPIRES_AT=$expires_at" >> "$TOKEN_FILE"

    # --- MODIFICATION: Convert timestamp to human-readable date ---
    human_readable_date=$(date -r "$expires_at" +"%Y-%m-%d %H:%M:%S")
    echo "Copilot Session Token obtained. Expires: $human_readable_date" >&2
    return 0 # Success
  else
    echo "Failed to get Copilot Session Token with provided GitHub PAT." >&2
    echo "Response: $copilot_token_response" >&2 # Debugging output
    return 1 # Failure
  fi
}

# Try to use existing GitHub PAT
if [[ -f "$GITHUB_PAT_FILE" ]]; then
  GITHUB_PAT=$(cat "$GITHUB_PAT_FILE")
  echo "Attempting to renew Copilot Session Token using saved GitHub PAT..." >&2
  if get_copilot_session_token "$GITHUB_PAT"; then
    echo "Copilot Session Token renewed successfully." >&2
    exit 0
  else
    echo "Saved GitHub PAT failed to renew token. Proceeding with full login." >&2
  fi
fi

echo "--- Step 1: Get Device Code ---"  >&2
response=$(curl -fS -s -X POST \
  https://github.com/login/device/code \
  -H "Content-Type: application/json" \
  -H "editor-plugin-version: gptel/*" \
  -H "editor-version: emacs/29.1" \
  -d '{ \
    "client_id": "Iv1.b507a08c87ecfe98", \
    "scope": "read:user" \
  }')

device_code=$(echo "$response" | sed -E -n 's/.*device_code=([^&]+).*/\1/p')
user_code=$(echo "$response" | sed -E -n 's/.*user_code=([^&]+).*/\1/p')
verification_uri=$(echo "$response" | sed -E -n 's/.*verification_uri=([^&]+).*/\1/p')
interval=$(echo "$response" | sed -E -n 's/.*interval=([^&]+).*/\1/p')

# --- MODIFICATION: URL-decode the verification URI ---
decoded_uri=$(printf '%b' "${verification_uri//%/\\x}")
echo "Please go to this URL in your browser: $decoded_uri"

echo "Enter this code: $user_code"
echo "Press Enter after you have authorized the application in your browser."
read -r

echo "--- Step 2: Poll for Access Token ---"  >&2
# Loop to poll for the access token
while true; do
  access_token_response=$(curl -fS -s -X POST \
    https://github.com/login/oauth/access_token \
    -H "Content-Type: application/json" \
    -H "editor-plugin-version: gptel/*" \
    -H "editor-version: emacs/29.1" \
    -d '{ \
      "client_id": "Iv1.b507a08c87ecfe98", \
      "device_code": "'"$device_code"'", \
      "grant_type": "urn:ietf:params:oauth:grant-type:device_code" \
    }') \

  # If response is empty, assume authorization is pending and continue polling \
  if [[ -z "$access_token_response" ]]; then
    echo "Authorization pending (empty response)... waiting $interval seconds." >&2
    sleep "$interval"
    continue
  fi

  error=$(echo "$access_token_response" | sed -E -n 's/.*error=([^&]+).*/\1/p' || true)

  if [[ "$error" == "authorization_pending" ]]; then
    echo "Authorization pending... waiting $interval seconds." >&2
    sleep "$interval"
  elif [[ "$error" == "slow_down" ]]; then
    # Increase interval if server asks to slow down
    interval=$((interval + 5))
    echo "Slow down... increasing wait time to $interval seconds." >&2
    sleep "$interval"
  elif [[ "$error" == "access_denied" ]]; then
    echo "Authorization denied. Exiting." >&2
    exit 1
  elif [[ "$error" == "expired_token" ]]; then
    echo "Device code expired. Exiting." >&2
    exit 1
  else
    github_pat=$(echo "$access_token_response" | sed -E -n 's/.*access_token=([^&]+).*/\1/p')
    echo "GitHub PAT obtained." >&2
    break
  fi
done

# Save GitHub PAT for future renewals
echo "$github_pat" > "$GITHUB_PAT_FILE"
echo "GitHub PAT saved to $GITHUB_PAT_FILE" >&2

echo "--- Step 3: Get Copilot Session Token ---" >&2
get_copilot_session_token "$github_pat"

echo "Login process complete." >&2
