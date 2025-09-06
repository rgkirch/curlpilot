#!/bin/bash

TEMP_RESPONSE_FILE="" # Initialize for trap
# Ensure temporary files are cleaned up on exit or interruption
trap '[ -n "$TEMP_RESPONSE_FILE" ] && rm -f "$TEMP_RESPONSE_FILE"' EXIT

# Check for tac dependency
if ! command -v tac >/dev/null 2>&1; then
  echo "Error: 'tac' command not found. Please install coreutils (e.g., 'brew install coreutils' on macOS, 'sudo apt-get install coreutils' on Debian/Ubuntu)." >&2
  exit 1
fi

# Load user configuration if available
# Users can customize settings by copying default_config.sh to ~/.config/curlpilot/config.sh
# and modifying it there.
CONFIG_DIR="$HOME/.config/curlpilot" # Define CONFIG_DIR early for sourcing

# Load default configuration first
if [ -f "$(dirname "$0")/default_config.sh" ]; then
  source "$(dirname "$0")/default_config.sh"
fi

# Overlay with user configuration if available
# Users can customize settings by copying default_config.sh to ~/.config/curlpilot/config.sh
# and modifying it there.
if [ -f "$CONFIG_DIR/config.sh" ]; then
  source "$CONFIG_DIR/config.sh"
fi

# Default color if not set in config.sh or default_config.sh
: ${SUMMARIZE_COLOR:="\033[0;33m"} # Yellow
COLOR_RESET="\033[0m"

# Default values for variables that might not be set in config files
: ${LLM_TOKEN_LIMIT:=8000}
: ${CHARS_PER_TOKEN:=4}
: ${CONFIG_DIR:="$HOME/.config/curlpilot"}
: ${HISTORY_FILE:="$CONFIG_DIR/convo_history.txt"}
: ${SUMMARIZATION_LEVEL:="NORMAL"}

CHAT_SCRIPT="$(dirname "$0")/chat.sh"


SUMMARIZE_THRESHOLD=$((LLM_TOKEN_LIMIT * CHARS_PER_TOKEN))

# Ensure the config directory exists
mkdir -p "$CONFIG_DIR"

# Function to summarize history
summarize_history() {
  echo -e "${SUMMARIZE_COLOR}History is getting too large. Asking Copilot to summarize...${COLOR_RESET}" >&2

  # Read the full history
  FULL_HISTORY=$(cat "$HISTORY_FILE")

  # Craft a summarization prompt based on the configured level
  case "$SUMMARIZATION_LEVEL" in
    CONCISE)
      SUMMARIZATION_PROMPT="${SUMMARIZATION_PROMPT_CONCISE}${FULL_HISTORY}"
      ;;
    DETAILED)
      SUMMARIZATION_PROMPT="${SUMMARIZATION_PROMPT_DETAILED}${FULL_HISTORY}"
      ;;
    *)
      # Default to NORMAL if not specified or invalid
      SUMMARIZATION_PROMPT="${SUMMARIZATION_PROMPT_NORMAL}${FULL_HISTORY}"
      ;;
  esac

  # Send summarization request to chat.sh
  # The output is captured here because it's used to update the history file.
  SUMMARIZED_HISTORY=$("$CHAT_SCRIPT" --stream=true <<< "$SUMMARIZATION_PROMPT")

  # Replace history file with summarized content
  echo "$SUMMARIZED_HISTORY" > "$HISTORY_FILE"
  echo "History summarized and updated." >&2
}

while true; do
  # Check history size before processing new input
  if [ -f "$HISTORY_FILE" ]; then
    CURRENT_HISTORY_CHARS=$(wc -m < "$HISTORY_FILE")
    if (( CURRENT_HISTORY_CHARS > SUMMARIZE_THRESHOLD )); then
      summarize_history
    fi
  fi

  echo "Enter your message (press Ctrl+D when finished, Ctrl+C to exit):"

  # Read multi-line input until Ctrl+D
  PROMPT=$(cat)

  if [ -z "$PROMPT" ]; then
    echo "No input provided. Exiting loop."
    break # Exit the loop if no input is given (Ctrl+D on empty line)
  fi

  # Append user's prompt to history file
  echo "User: $PROMPT" >> "$HISTORY_FILE"

  # Read existing history (which now includes the latest user prompt)
  CURRENT_HISTORY=""
  if [ -f "$HISTORY_FILE" ]; then
    CURRENT_HISTORY=$(cat "$HISTORY_FILE")
  fi

  # The full payload for chat.sh is simply the current history
  FULL_PAYLOAD="$CURRENT_HISTORY"

  echo "Sending to chat.sh..."
  # Execute chat.sh with the full payload, stream its output, and save to a temporary file
  TEMP_RESPONSE_FILE=$(mktemp)
  "$CHAT_SCRIPT" --stream=true <<< "$FULL_PAYLOAD" | tee "$TEMP_RESPONSE_FILE"

  # Append chat.sh response from temp file to history file
  echo "" >> "$HISTORY_FILE" # Add a newline before Copilot's response for clarity in history
  # Trim leading/trailing newlines from the response before saving to history.
  # This pipeline uses sed and tac to remove blank lines from the beginning and end of the output.
  # Note: 'tac' is not available on all systems (e.g., macOS by default). It is part of GNU coreutils.
  echo "Copilot: $(cat "$TEMP_RESPONSE_FILE" | sed '/./,$!d' | tac | sed '/./,$!d' | tac)" >> "$HISTORY_FILE"

  echo # Add a newline for better readability between responses
done
