# copilot/login.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"
register_dep parse_args "parse_args.bash"

source "$(resolve_path config.bash)"

JOB_TICKET_JSON=$(jq --null-input \
  '{spec: $spec, args: $ARGS.positional}' \
  --argjson spec '{
  "refresh_session_token": {
    "type": "boolean",
    "default": false,
    "description": "Force a refresh of the Copilot session token, ignoring any cached valid token."
  }
}' --args -- "$@")

PARSED_ARGS_JSON=$(exec_dep parse_args "$JOB_TICKET_JSON")
FORCE_REFRESH=$(jq --raw-output '.refresh_session_token' <<< "$PARSED_ARGS_JSON")

GITHUB_PAT_FILE="$CURLPILOT_CONFIG_DIR/github_pat.txt"
TOKEN_FILE="$CURLPILOT_CONFIG_DIR/token.json"

# --- Token Cache Check ---
if [[ "$FORCE_REFRESH" = false && -f "$TOKEN_FILE" ]]; then
  token_json="$(cat "$TOKEN_FILE")"
  cached_token="$(jq -r '.session_token // empty' <<< "$token_json")"
  cached_expires_at="$(jq -r '.expires_at // empty' <<< "$token_json")"

  if [[ -n "$cached_token" && -n "$cached_expires_at" ]]; then
    current_time=$(date +%s)
    # Check if token is not expired (with a 60-second buffer)
    if (( current_time < (cached_expires_at - 60) )); then
      echo "Copilot token is still valid from cache." >&2
      # Print the valid token JSON and exit successfully.
      echo "$token_json"
      exit 0
    else
      echo "Copilot token has expired. Refreshing..." >&2
    fi
  fi
fi

# --- Token Renewal/Acquisition Logic ---

get_copilot_session_token() {
  local github_pat="$1"
  copilot_token_response=$(curl -fS -s -X GET \
    https://api.github.com/copilot_internal/v2/token \
    -H "Authorization: token $github_pat" \
    -H "Editor-Plugin-Version: gptel/*" \
    -H "Editor-Version: emacs/29.1")

  local copilot_session_token=$(jq -r '.token // empty' <<< "$copilot_token_response")
  local expires_at=$(jq -r '.expires_at // empty' <<< "$copilot_token_response")

  if [[ -n "$copilot_session_token" && -n "$expires_at" ]]; then
        jq -n \
      --arg token "$copilot_session_token" \
      --argjson expires "$expires_at" \
      '{session_token: $token, expires_at: $expires}' > "$TOKEN_FILE"

    human_readable_date=$(date -d @"$expires_at" +"%Y-%m-%d %H:%M:%S")
    echo "Copilot Session Token obtained. Expires: $human_readable_date" >&2
    return 0 # Success
  else
    echo "Failed to get Copilot Session Token with provided GitHub PAT." >&2
    echo "Response: $copilot_token_response" >&2
    return 1 # Failure
  fi
}

if [[ -f "$GITHUB_PAT_FILE" ]]; then
  GITHUB_PAT=$(cat "$GITHUB_PAT_FILE")
  echo "Attempting to renew Copilot Session Token using saved GitHub PAT..." >&2
  if get_copilot_session_token "$GITHUB_PAT"; then
    echo "Copilot Session Token renewed successfully." >&2
  else
    echo "Saved GitHub PAT failed to renew token. Proceeding with full login." >&2
  fi
else
  # --- Full Device Flow ---
  echo "--- Step 1: Get Device Code ---" >&2
  response=$(curl -fS -s -X POST \
    https://github.com/login/device/code \
    -H "Content-Type: application/json" \
    -d '{ "client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user" }')
  device_code=$(sed -E -n 's/.*device_code=([^&]+).*/\1/p' <<< "$response")
  user_code=$(sed -E -n 's/.*user_code=([^&]+).*/\1/p' <<< "$response")
  verification_uri=$(sed -E -n 's/.*verification_uri=([^&]+).*/\1/p' <<< "$response")
  interval=$(sed -E -n 's/.*interval=([^&]+).*/\1/p' <<< "$response")
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
    error=$(sed -E -n 's/.*error=([^&]+).*/\1/p' <<< "$access_token_response" || true)
    if [[ "$error" == "authorization_pending" ]]; then
      echo "Authorization pending... waiting $interval seconds." >&2; sleep "$interval"
    elif [[ "$error" == "slow_down" ]]; then
      interval=$((interval + 5)); echo "Slow down... increasing wait time to $interval seconds." >&2; sleep "$interval"
    elif [[ "$error" == "access_denied" ]]; then
      echo "Authorization denied. Exiting." >&2; exit 1
    elif [[ "$error" == "expired_token" ]]; then
      echo "Device code expired. Exiting." >&2; exit 1
    else
      github_pat=$(sed -E -n 's/.*access_token=([^&]+).*/\1/p' <<< "$access_token_response")
      if [[ -n "$github_pat" ]]; then
        echo "GitHub PAT obtained." >&2; break
      fi
      echo "Authorization pending (empty response)... waiting $interval seconds." >&2; sleep "$interval"
    fi
  done
  echo "$github_pat" > "$GITHUB_PAT_FILE"
  echo "GitHub PAT saved to $GITHUB_PAT_FILE" >&2
  echo "--- Step 3: Get Copilot Session Token ---" >&2
  get_copilot_session_token "$github_pat"
fi

# --- Final Output ---
if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "Login process failed to produce a valid token file." >&2
  exit 1
fi
cat "$TOKEN_FILE"
