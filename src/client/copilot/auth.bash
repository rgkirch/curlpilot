# copilot/auth.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep login "copilot/login.bash"

LOGIN_JSON=$(exec_dep login)

if [[ -z "$LOGIN_JSON" ]]; then
  echo "Error: auth.bash did not receive a response from the login provider." >&2
  exit 1
fi

echo "$LOGIN_JSON"
