# User-configurable settings for curlpilot.sh

# Color for summarization messages (ANSI escape codes)
# Example: Yellow (0;33), Cyan (0;36), Green (0;32), Red (0;31)
# Format: "\033[<style>;<color>m"
# Reset: "\033[0m"
SUMMARIZE_COLOR="\033[0;33m" # Default to Yellow

# LLM Token Limits and Character Conversion
LLM_TOKEN_LIMIT=8000
CHARS_PER_TOKEN=4

# Configuration for history and main config directory
CONFIG_DIR="$HOME/.config/curlpilot"
HISTORY_FILE="$CONFIG_DIR/convo_history.txt"

# Summarization Prompt Levels
# Users can choose the aggressiveness of summarization.
# Options: CONCISE, NORMAL, DETAILED
SUMMARIZATION_LEVEL="NORMAL"

# Use dirname to ensure sourcing works regardless of current directory
source "$(dirname "${BASH_SOURCE[0]}")/prompts/prompts.sh"

# Prompt for concise summarization
SUMMARIZATION_PROMPT_CONCISE=$(cat <<'EOF'
You are the assistant and this is your conversation history with the user but it has grown too long. Rewrite the following conversation to about 60% of its current size. Summarize the conversation history while preserving clear delineation of User Assistant speaker rolls interaction in only the most recent messages. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

# Prompt for normal summarization
SUMMARIZATION_PROMPT_NORMAL=""

# Prompt for detailed summarization
SUMMARIZATION_PROMPT_DETAILED=$(cat <<'EOF'
You are the assistant and this is your conversation history with the user. Rewrite the following conversation to about 80% of its current size while preserving clear delineation of User Assistant speaker rolls interaction. Use simple language and remove superfluous language while still preserving all detail.
EOF
)

