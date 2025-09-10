#!/usr/bin/env bash

set -euo pipefail

source deps.sh

LOGIN_SCRIPT="login.sh"

register parse_args "copilot/parse_chat_args.sh"
register login $LOGIN_SCRIPT

source_dep parse_args

#echo "TOKEN_FILE: $TOKEN_FILE"

read_and_check_token() {

  source_dep login

  if [[ -z "${COPILOT_SESSION_TOKEN-}" || -z "${EXPIRES_AT-}" ]]; then
    echo "Error: Token file is incomplete or malformed. Please run $LOGIN_SCRIPT again." >&2
    exit 1
  fi

  current_time=$(date +%s)
  # Add a 60-second buffer to be safe
  if (( current_time > (EXPIRES_AT - 60) )); then
    echo "Copilot token has expired or is about to. Attempting to refresh..." >&2
    if "$LOGIN_SCRIPT"; then # Call login.sh to refresh token
      source "$TOKEN_FILE" # Reload new token
      echo "Token refreshed successfully." >&2
    else
      echo "Failed to refresh token. Please run $LOGIN_SCRIPT manually." >&2
      exit 1
    fi
  fi
}
