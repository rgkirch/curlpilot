# gemini/auth.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

register_dep config "config.bash"

# Get the full config, then extract the gemini-specific part
FULL_CONFIG=$(exec_dep config)
GEMINI_CONFIG=$(echo "$FULL_CONFIG" | jq --compact-output '.gemini')

# Extract the path to the credentials file from the gemini config
CREDS_FILE_PATH=$(echo "$GEMINI_CONFIG" | jq -r '.oauth_creds_path // "\($ENV.HOME)/.gemini/oauth_creds.json"')

if [[ -z "$CREDS_FILE_PATH" || "$CREDS_FILE_PATH" == "null" ]]; then
  echo "Error: 'oauth_creds_path' not found in Gemini config." >&2
  exit 1
fi

if [[ ! -f "$CREDS_FILE_PATH" ]]; then
  echo "Error: Gemini credentials file not found at $CREDS_FILE_PATH" >&2
  exit 1
fi

ACCESS_TOKEN=$(jq -r '.access_token' "$CREDS_FILE_PATH")
EXPIRY_DATE=$(jq -r '.expiry_date // 0' "$CREDS_FILE_PATH") # Read expiry_date, default to 0 if not found

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "Error: Failed to get access token from $CREDS_FILE_PATH" >&2
  exit 1
fi

# Check if the token is close to expiring
if [[ "$EXPIRY_DATE" -ne 0 ]]; then
  CURRENT_TIME_MS=$(date +%s%3N) # Current time in milliseconds
  # Warn if expiring within the next 5 minutes (300,000 milliseconds)
  EXPIRY_THRESHOLD_MS=300000
  if (( (EXPIRY_DATE - CURRENT_TIME_MS) < EXPIRY_THRESHOLD_MS )); then
    echo "Warning: Gemini access token is close to expiring (in less than 5 minutes)." >&2
    echo "Please refresh your credentials." >&2
  fi
fi

# Perform loadCodeAssist call to get the project ID
LOAD_CODE_ASSIST_RESPONSE=$(curl -sS -X POST "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"metadata":{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}')

PROJECT_ID=$(echo "$LOAD_CODE_ASSIST_RESPONSE" | jq -r '.cloudaicompanionProject // empty')

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "Error: Failed to get project ID from loadCodeAssist response." >&2
  echo "Response: $LOAD_CODE_ASSIST_RESPONSE" >&2
  exit 1
fi

jq -n \
  --arg access_token "$ACCESS_TOKEN" \
  --arg project_id "$PROJECT_ID" \
  '{access_token: $access_token, project_id: $project_id}'
