#!/bin/bash

set -euox pipefail

# curlpilot/copilot/auth.sh

source "$(dirname "$0")/../deps.sh"

LOGIN_SCRIPT="login.sh"

# This script takes no arguments. The spec is an empty object.
ARG_SPEC_JSON="{}"

register parse_args "parse_args.sh"
# We execute parse_args to validate that no arguments were passed.
# The output is ignored, but the script will exit if unknown args are found.
exec_dep parse_args "$ARG_SPEC_JSON" "$@"

register login $LOGIN_SCRIPT
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
