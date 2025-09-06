#!/bin/bash

CONFIG_DIR="$HOME/.config/curlpilot"
HISTORY_FILE="$CONFIG_DIR/convo_history.txt"

LLM_TOKEN_LIMIT=8000
CHARS_PER_TOKEN=4
SUMMARIZE_THRESHOLD=$((LLM_TOKEN_LIMIT * CHARS_PER_TOKEN))

# Ensure the config directory exists
mkdir -p "$CONFIG_DIR"

# Function to summarize history
summarize_history() {
  echo "History is getting too large. Asking Copilot to summarize..." >&2

  # Read the full history
  FULL_HISTORY=$(cat "$HISTORY_FILE")

  # Craft a summarization prompt
  SUMMARIZATION_PROMPT="The following is a conversation history. Please summarize it concisely, using more abstract language and omitting unimportant details, to serve as context for future conversation turns. Do not add any conversational filler, just the summarized history:\n\n$FULL_HISTORY"

  # note to self
  "Please summarize the following conversation history as context for future turns. Preserve all key instructions, facts, and examples, especially code or technical details. Be concise, omit unimportant or repetitive chatter, and do not add conversational filler."

  # Send summarization request to chat.sh
  SUMMARIZED_HISTORY=$(/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/chat.sh --stream=true <<< "$SUMMARIZATION_PROMPT")

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
  # Execute chat.sh with the full payload and capture its output
  CHAT_RESPONSE=$(/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/chat.sh <<< "$FULL_PAYLOAD")

  # Append chat.sh response to history file
  echo "Copilot: $CHAT_RESPONSE" >> "$HISTORY_FILE"

  # Display chat.sh response
  echo "Copilot: $CHAT_RESPONSE"
  echo # Add a newline for better readability between responses
done
