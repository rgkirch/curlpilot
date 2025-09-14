#!/bin/bash
set -euo pipefail

# This script acquires a Copilot session token and outputs it as a JSON object.
# It uses ~/.config/curlpilot/ for caching credentials.

source "$(dirname "$0")/../deps.sh"
register parse_args "parse_args.sh"

# --- Argument Parsing ---
read -r -d '' ARG_SPEC_JSON <<'EOF'
{
  "refresh_session_token": {
    "type": "boolean",
    "default": false,
    "description": "Force a refresh of the Copilot session token, ignoring any cached valid token."
  }
}
EOF

ARGS_AS_JSON=$(jq --null-input --compact-output --args "$@")
JOB_TICKET_JSON=$(jq --null-input \
  --argjson spec "$ARG_SPEC_JSON" \
  --argjson args "$ARGS_AS_JSON" \
  '{"spec": $spec, "args": $args}')

PARSED_ARGS_JSON=$(exec_dep parse_args "$JOB_TICKET_JSON")
FORCE_REFRESH=$(echo "$PARSED_ARGS_JSON" | jq --raw-output '.refresh_session_token')


# --- Setup Paths ---
CONFIG_DIR="$HOME/.config/curlpilot"
mkdir -p "$CONFIG_DIR"
GITHUB_PAT_FILE="$CONFIG_DIR/github_pat.txt"
TOKEN_FILE="$CONFIG_DIR/token.txt"


# --- Token Cache Check ---
if [[ "$FORCE_REFRESH" = false && -f "$TOKEN_FILE" ]]; then
  source "$TOKEN_FILE"
  if [[ -n "${EXPIRES_AT-}" ]]; then
    current_time=$(date +%s)
    # Check if token is not expired (with a 60-second buffer)
    if (( current_time < (EXPIRES_AT - 60) )); then
      echo "Copilot token is still valid from cache." >&2
      # Print the valid token as JSON and exit successfully
      printf '{"session_token":"%s","expires_at":%d}\n' "$COPILOT_SESSION_TOKEN" "$EXPIRES_AT"
      exit 0
    else
      echo "Copilot token has expired. Refreshing..." >&2
    fi
  fi
fi


# --- Token Renewal/Acquisition Logic ---

# Function to get Copilot session token using GitHub PAT
get_copilot_session_token() {
  local github_pat="$1"
  copilot_token_response=$(curl -fS -s -X GET \
    https://api.github.com/copilot_internal/v2/token \
    -H "Authorization: token $github_pat" \
    -H "Editor-Plugin-Version: gptel/*" \
    -H "Editor-Version: emacs/29.1")

  local copilot_session_token=$(echo "$copilot_token_response" | jq --raw-output '.token' || true)
  local expires_at=$(echo "$copilot_token_response" | jq --raw-output '.expires_at' || true)

  if [[ -n "$copilot_session_token" && "$copilot_session_token" != "null" && -n "$expires_at" ]]; then
    # Write to the cache file
    echo "COPILOT_SESSION_TOKEN='$copilot_session_token'" > "$TOKEN_FILE"
    echo "EXPIRES_AT=$expires_at" >> "$TOKEN_FILE"

    human_readable_date=$(date -d @"$expires_at" +"%Y-%m-%d %H:%M:%S")
    echo "Copilot Session Token obtained. Expires: $human_readable_date" >&2
    return 0 # Success
  else
    echo "Failed to get Copilot Session Token with provided GitHub PAT." >&2
    echo "Response: $copilot_token_response" >&2
    return 1 # Failure
  fi
}

# Try to use existing GitHub PAT from cache
if [[ -f "$GITHUB_PAT_FILE" ]]; then
  GITHUB_PAT=$(cat "$GITHUB_PAT_FILE")
  echo "Attempting to renew Copilot Session Token using saved GitHub PAT..." >&2
  if get_copilot_session_token "$GITHUB_PAT"; then
    echo "Copilot Session Token renewed successfully." >&2
    # The function updated the cache; now we fall through to the final output section
  else
    echo "Saved GitHub PAT failed to renew token. Proceeding with full login." >&2
    # Fall through to the device flow
  fi
else
  # --- Full Device Flow ---
  echo "--- Step 1: Get Device Code ---" >&2
  response=$(curl -fS -s -X POST \
    https://github.com/login/device/code \
    -H "Content-Type: application/json" \
    -d '{ "client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user" }')

  device_code=$(echo "$response" | sed -E -n 's/.*device_code=([^&]+).*/\1/p')
  user_code=$(echo "$response" | sed -E -n 's/.*user_code=([^&]+).*/\1/p')
  verification_uri=$(echo "$response" | sed -E -n 's/.*verification_uri=([^&]+).*/\1/p')
  interval=$(echo "$response" | sed -E -n 's/.*interval=([^&]+).*/\1/p')

  decoded_uri=$(printf '%b' "${verification_uri//%/\\x}")
  echo "Please go to this URL in your browser: $decoded_uri" >&2
  echo "Enter this code: $user_code" >&2
  echo "Press Enter after you have authorized the application in your browser." >&2
  read -r

  echo "--- Step 2: Poll for Access Token ---" >&2
  while true; do
    access_token_response=$(curl -fS -s -X POST \
      https://github.com/login/oauth/access_token \
      -H "Content-Type: application/json" \
      -d '{ "client_id": "Iv1.b507a08c87ecfe98", "device_code": "'"$device_code"'", "grant_type": "urn:ietf:params:oauth:grant-type:device_code" }')

    # ... (polling logic remains the same) ...
    error=$(echo "$access_token_response" | sed -E -n 's/.*error=([^&]+).*/\1/p' || true)
    if [[ "$error" == "authorization_pending" ]]; then
      echo "Authorization pending... waiting $interval seconds." >&2; sleep "$interval"
    elif [[ "$error" == "slow_down" ]]; then
      interval=$((interval + 5)); echo "Slow down... increasing wait time to $interval seconds." >&2; sleep "$interval"
    elif [[ "$error" == "access_denied" ]]; then
      echo "Authorization denied. Exiting." >&2; exit 1
    elif [[ "$error" == "expired_token" ]]; then
      echo "Device code expired. Exiting." >&2; exit 1
    else
      github_pat=$(echo "$access_token_response" | sed -E -n 's/.*access_token=([^&]+).*/\1/p')
      if [[ -n "$github_pat" ]]; then
        echo "GitHub PAT obtained." >&2; break
      fi
      echo "Authorization pending (empty response)... waiting $interval seconds." >&2; sleep "$interval"
    fi
  done

  # Save GitHub PAT to cache for future renewals
  echo "$github_pat" > "$GITHUB_PAT_FILE"
  echo "GitHub PAT saved to $GITHUB_PAT_FILE" >&2

  echo "--- Step 3: Get Copilot Session Token ---" >&2
  get_copilot_session_token "$github_pat"
fi


# --- Final Output ---
# After a successful login/refresh, the new token is in TOKEN_FILE. Load it.
source "$TOKEN_FILE"

# Validate that we have what we need
if [[ -z "${COPILOT_SESSION_TOKEN-}" || -z "${EXPIRES_AT-}" ]]; then
  echo "Login process failed to produce a valid token." >&2
  exit 1
fi

# Print the final JSON object to stdout
printf '{"session_token":"%s","expires_at":%d}\n' "$COPILOT_SESSION_TOKEN" "$EXPIRES_AT"
