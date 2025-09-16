# config.bash
set -euo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME environment variable is not set." >&2
  exit 1
fi

CURLPILOT_CONFIG_DIR=${CURLPILOT_CONFIG_DIR:-"$HOME/.config/curlpilot"}
if [[ ! -d "$CURLPILOT_CONFIG_DIR" ]]; then
  mkdir -p "$CURLPILOT_CONFIG_DIR"
fi

TOKEN_FILE="$CURLPILOT_CONFIG_DIR/token.txt"
