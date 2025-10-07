# config.bash
set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/logging.bash"

if [[ -z "${HOME:-}" ]]; then
  echo "Error: HOME environment variable is not set." >&2
  exit 1
fi

CURLPILOT_CONFIG_DIR=${CURLPILOT_CONFIG_DIR:-"$HOME/.config/curlpilot"}
if [[ ! -d "$CURLPILOT_CONFIG_DIR" ]]; then
  mkdir -p "$CURLPILOT_CONFIG_DIR"
fi

TOKEN_FILE="$CURLPILOT_CONFIG_DIR/token.txt"

GEMINI_SETTINGS_FILE="$CURLPILOT_CONFIG_DIR/gemini_settings.json"
if [[ ! -f "$GEMINI_SETTINGS_FILE" ]]; then
  echo '{}' > "$GEMINI_SETTINGS_FILE"
fi

COPILOT_SETTINGS_FILE="$CURLPILOT_CONFIG_DIR/copilot_settings.json"
if [[ ! -f "$COPILOT_SETTINGS_FILE" ]]; then
  echo '{}' > "$COPILOT_SETTINGS_FILE"
fi

copilot_json=$(cat "$COPILOT_SETTINGS_FILE")
gemini_json=$(cat "$GEMINI_SETTINGS_FILE")

log_debug "CURLPILOT_CONFIG_DIR: $CURLPILOT_CONFIG_DIR"

T="$(jq --null-input \
  --argjson copilot "$copilot_json" \
  --argjson gemini "$gemini_json" \
  --arg config_dir "$CURLPILOT_CONFIG_DIR" \
  '{copilot: $copilot, gemini: $gemini, config_dir: $config_dir}')"

log_debug "T $T"
echo "$T"
