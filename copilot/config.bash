# copilot/config.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../deps.bash"

DEFAULT_SETTINGS_FILE="$(resolve_path settings.json)"
USER_SETTINGS_FILE="$HOME/.config/curlpilot/copilot/settings.json"

# --- Read Configuration Files ---
# Read default settings, defaulting to an empty object if the file doesn't exist.
DEFAULT_JSON=$(cat "$DEFAULT_SETTINGS_FILE" 2>/dev/null || echo '{}')

# Read user-specific settings, also defaulting to an empty object.
USER_JSON=$(cat "$USER_SETTINGS_FILE" 2>/dev/null || echo '{}')


# --- Merge and Output ---
# Use jq's slurp mode to read both JSON objects into an array.
# The '+' operator merges the objects, with the second object (user settings)
# overriding any keys from the first (defaults).
jq --slurp '.[0] + .[1]' <(echo "$DEFAULT_JSON") <(echo "$USER_JSON")
