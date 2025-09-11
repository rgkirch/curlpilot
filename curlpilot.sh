#!/bin/bash

set -euo pipefail

# Main script for curlpilot, using a branching conversation model.

# --- Configuration ---
# Load default config
if [ -f "$(dirname "$0")/default_config.sh" ]; then
  source "$(dirname "$0")/default_config.sh"
fi

# Load user config
USER_CONFIG_DIR="$HOME/.config/curlpilot"
if [ -f "$USER_CONFIG_DIR/config.sh" ]; then
  source "$USER_CONFIG_DIR/config.sh"
fi

# Path to the chat script
: ${CHAT_SCRIPT:="$(dirname "$0")/copilot/chat.sh"} # Updated default path

# Default model and API endpoint
: ${MODEL:="gpt-4.1"}
: ${API_ENDPOINT:="https://api.githubcopilot.com/chat/completions"}
: ${STREAM_ENABLED:=true} # Default stream setting

# --- Dependency Checks ---
if ! "$(dirname "$0")/check_deps.sh"; then
    exit 1
fi

# --- Usage Function ---
print_usage() {
    echo "Usage: $0 [options]"
    echo "  An interactive chat script that maintains conversation history."
    echo
    echo "Options:"
    echo "  --new-convo           Start a new conversation instead of continuing the last one."
    echo "  --config-dir=<path>   Override the default configuration directory (~/.config/curlpilot/conversations)."
    echo "  --model=<name>        Specify the AI model to use (e.g., gpt-4.1). Default: $MODEL"
    echo "  --api-endpoint=<url>  Specify the API endpoint for the chat service. Default: $API_ENDPOINT"
    echo "  --stream=true|false   Enable or disable streaming responses. Default: $STREAM_ENABLED"
    echo "  --help                Display this help message and exit."
}

# --- Global State ---
FORCE_NEW_CONVO=false
CURLPILOT_CONFIG_DIR_OVERRIDE=""

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --new-convo) FORCE_NEW_CONVO=true ; shift ;;
        --config-dir=*) CURLPILOT_CONFIG_DIR_OVERRIDE="${1#*=}" ; shift ;;
        --chat-script=*) CHAT_SCRIPT="${1#*=}" ; shift ;;
        --model=*) MODEL="${1#*=}" ; shift ;;
        --api-endpoint=*) API_ENDPOINT="${1#*=}" ; shift ;;
        --stream=*) STREAM_ENABLED="${1#*=}" ; shift ;;
        --help) print_usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
    esac
done

# --- Set final configuration directory
if [ -n "$CURLPILOT_CONFIG_DIR_OVERRIDE" ]; then
    CURLPILOT_CONFIG_DIR="$CURLPILOT_CONFIG_DIR_OVERRIDE"
else
    : ${CURLPILOT_CONFIG_DIR:="$HOME/.config/curlpilot/conversations"}
fi

# --- Core Functions ---

# Finds the latest conversation dir, or creates a new one.
# Exports ACTIVE_CONVO_DIR for other functions to use.
get_active_convo_dir() {
    mkdir -p "$CURLPILOT_CONFIG_DIR"

    if [ "$FORCE_NEW_CONVO" = true ]; then
        ACTIVE_CONVO_DIR="$CURLPILOT_CONFIG_DIR/$(date +'%Y%m%d_%H%M%S')"
    else
        # Find the most recent directory by modification time
        ACTIVE_CONVO_DIR=$(find "$CURLPILOT_CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
        if [ -z "$ACTIVE_CONVO_DIR" ]; then
            ACTIVE_CONVO_DIR="$CURLPILOT_CONFIG_DIR/$(date +'%Y%m%d_%H%M%S')"
        fi
    fi

    if [ ! -d "$ACTIVE_CONVO_DIR" ]; then
        mkdir -p "$ACTIVE_CONVO_DIR"
        # A new conversation has no messages, so metadata is minimal.
        jq -n '{leaf_ids: [], active_leaf_id: null}' > "$ACTIVE_CONVO_DIR/metadata.json"
    fi
    export ACTIVE_CONVO_DIR
}

# Returns the sharded path for a given message UUID.
# Arg 1: UUID
get_message_path() {
    local uuid="$1"
    local dir_prefix="${uuid:0:2}"
    local filename_suffix="${uuid:2}"
    echo "$ACTIVE_CONVO_DIR/$dir_prefix/$filename_suffix.json"
}

# Saves a message to a new UUID file and updates metadata.
# Takes role and content as arguments.
save_message() {
    local role="$1"
    local content="$2"
    local metadata_file="$ACTIVE_CONVO_DIR/metadata.json"

    local new_uuid=$(uuidgen)
    local parent_id=$(jq -r '.active_leaf_id' "$metadata_file")

    local file_path=$(get_message_path "$new_uuid")
    mkdir -p "$(dirname "$file_path")"

    # Create the new message file, including the parent_id link
    jq -n \
      --arg role "$role" \
      --arg content "$content" \
      --arg parent_id "$parent_id" \
      '{role: $role, content: $content, parent_id: $parent_id}' > "$file_path"

    # Update metadata: remove old leaf (if exists), add new leaf, set as active
    local temp_metadata=$(mktemp)
    jq \
      --arg new_leaf_id "$new_uuid" \
      --arg old_leaf_id "$parent_id" \
      '(.leaf_ids -= [$old_leaf_id]) | .leaf_ids += [$new_leaf_id] | .active_leaf_id = $new_leaf_id' \
      "$metadata_file" > "$temp_metadata" && mv "$temp_metadata" "$metadata_file"
}

# Builds the JSON payload by walking up the conversation tree from the active leaf.
build_payload() {
    local metadata_file="$ACTIVE_CONVO_DIR/metadata.json"
    local current_id=$(jq -r '.active_leaf_id' "$metadata_file")

    local messages='[]'

    while [ -n "$current_id" ] && [ "$current_id" != "null" ]; do
        local msg_file=$(get_message_path "$current_id")
        if [ ! -f "$msg_file" ]; then
            echo "Error: Message file not found for ID $current_id" >&2
            break
        fi

        local message_content=$(cat "$msg_file")
        # We only need role and content for the payload
        local payload_msg=$(jq '{role, content}' <<< "$message_content")

        messages=$(jq --argjson msg "$payload_msg" '[$msg] + .' <<< "$messages")

        # Move to the parent
        current_id=$(jq -r '.parent_id' "$msg_file")
    done

    echo "$messages"
}

# --- Main Loop ---

get_active_convo_dir

# In interactive mode, let the user know how to submit their message.
if [ -t 0 ]; then
    echo "Enter your message (Ctrl+D when finished, Ctrl+C to exit):"
fi

# This `while read` loop is the core of the fix.
# 1. `IFS= read -r`: A robust way to read input without mangling it.
# 2. `-d $'\x04'`: Sets the End-of-Transmission character (Ctrl+D) as the message delimiter.
# 3. `|| [[ -n "$PROMPT" ]]`: A crucial part that ensures the loop processes the final message
#    if the input stream doesn't end with the delimiter.
while IFS= read -r -d $'\x04' PROMPT || [[ -n "$PROMPT" ]]; do
    # Skip any empty messages that might occur from consecutive delimiters.
    if [ -z "$PROMPT" ]; then
        continue
    fi

    save_message "user" "$PROMPT"

    # Build the payload by walking the current branch
    PAYLOAD=$(build_payload)

    echo "Sending to chat.sh..." >&2
    TEMP_RESPONSE_FILE=$(mktemp)
    # Ensure trap cleans up the temp file
    trap 'rm -f "$TEMP_RESPONSE_FILE"' EXIT

    # Stream the response to the terminal AND save it to a temp file.
    "$CHAT_SCRIPT" --stream="$STREAM_ENABLED" --model="$MODEL" --api-endpoint="$API_ENDPOINT" <<< "$PAYLOAD" | tee "$TEMP_RESPONSE_FILE"

    # Read the full response from the temp file for saving.
    ASSISTANT_RESPONSE=$(cat "$TEMP_RESPONSE_FILE")

    if [ -n "$ASSISTANT_RESPONSE" ]; then
        save_message "assistant" "$ASSISTANT_RESPONSE"
    fi

    echo
done
