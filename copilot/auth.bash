#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../deps.sh"

register login "login.sh"

LOGIN_JSON=$(exec_dep login)

if [[ -z "$LOGIN_JSON" ]]; then
  echo "Error: auth.sh did not receive a response from the login provider." >&2
  exit 1
fi

echo "$LOGIN_JSON"
