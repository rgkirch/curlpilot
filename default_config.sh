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

# Prompt for concise summarization
SUMMARIZATION_PROMPT_CONCISE="The following is a conversation history. Summarize it very briefly, focusing only on the most critical facts and instructions. Omit all conversational filler and abstract details."

# Prompt for normal summarization
SUMMARIZATION_PROMPT_NORMAL="The following is a conversation history. Please summarize it concisely, using more abstract language and omitting unimportant details, to serve as context for future conversation turns. Do not add any conversational filler, just the summarized history:"

# Prompt for detailed summarization
SUMMARIZATION_PROMPT_DETAILED="The following is a conversation history. Preserve User/Assistant interaction but use simple language and remove superfluous language while still preserving all detail."
