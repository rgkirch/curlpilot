#!/bin/bash
set -euo pipefail

# curlpilot/context_calculator.bash

# Calculates how many messages in a branch fit within a token limit.

# --- Configuration ---
: ${CURLPILOT_CONFIG_DIR:="$HOME/.config/curlpilot/conversations"}
: ${CHARS_PER_TOKEN:=4}

# --- Dependency Checks ---
if ! "$(dirname "$0")/check_deps.bash"; then
    exit 1
fi

# --- Argument Parsing ---
if [ -z "$1" ]; then
    echo "Usage: $0 <token_limit> [--start-from=<uuid>] [--convo-dir=<path>]" >&2
    echo "Error: Token limit not provided." >&2
    exit 1
fi

TOKEN_LIMIT="$1"
shift # Move past the mandatory argument

# Check if TOKEN_LIMIT is a valid integer
if ! [[ "$TOKEN_LIMIT" =~ ^[0-9]+$ ]]; then
    echo "Error: Token limit must be a positive integer." >&2
    exit 1
fi

# Handle optional flags
START_FROM_ARG=""
CONVO_DIR_ARG=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --start-from=*) START_FROM_ARG="${1#*=}" ; shift ;;
        --convo-dir=*) CONVO_DIR_ARG="${1#*=}" ; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

# --- Directory and Metadata ---
ACTIVE_CONVO_DIR=""
if [ -n "$CONVO_DIR_ARG" ]; then
    if [ ! -d "$CONVO_DIR_ARG" ] || [ ! -f "$CONVO_DIR_ARG/metadata.json" ]; then
        echo "Error: Provided path '$CONVO_DIR_ARG' is not a valid conversation directory." >&2
        exit 1
    fi
    ACTIVE_CONVO_DIR="$CONVO_DIR_ARG"
else
    # Find the most recent directory if none is provided
    ACTIVE_CONVO_DIR=$(find "$CURLPILOT_CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
    if [ -z "$ACTIVE_CONVO_DIR" ]; then
        echo "Error: No conversations found in $CURLPILOT_CONFIG_DIR" >&2
        exit 1
    fi
fi

METADATA_FILE="$ACTIVE_CONVO_DIR/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
    echo "Error: metadata.json not found in $ACTIVE_CONVO_DIR" >&2
    exit 1
fi

# --- Core Logic ---

# Returns the sharded path for a given message UUID.
# Arg 1: UUID
get_message_path() {
    local uuid="$1"
    local dir_prefix="${uuid:0:2}"
    local filename_suffix="${uuid:2}"
    echo "$ACTIVE_CONVO_DIR/$dir_prefix/$filename_suffix.json"
}

# Determine the starting message ID for the traversal
start_node_id=""
if [ -n "$START_FROM_ARG" ]; then
    start_node_id="$START_FROM_ARG"
    # Verify the UUID exists as a file
    if [ ! -f "$(get_message_path "$start_node_id")" ]; then
        echo "Error: --start-from UUID '$start_node_id' does not correspond to a message file." >&2
        exit 1
    fi
else
    start_node_id=$(jq -r '.active_leaf_id' "$METADATA_FILE")
fi

if [ -z "$start_node_id" ] || [ "$start_node_id" == "null" ]; then
    echo 0
    exit 0
fi

tokens_used=0
messages_fit=0
current_id="$start_node_id"

# Walk backwards up the tree from the starting node
while [ -n "$current_id" ] && [ "$current_id" != "null" ]; do
    msg_file=$(get_message_path "$current_id")
    if [ ! -f "$msg_file" ]; then
        echo "Warning: Traversal failed. Message file not found for ID $current_id" >&2
        break
    fi

    # Read content and calculate tokens on the fly
    content=$(jq -r '.content' "$msg_file")
    msg_tokens=$(echo "$content" | wc -c | awk -v "chars_per_token=$CHARS_PER_TOKEN" '{print int($1 / chars_per_token)}')

    if (( tokens_used + msg_tokens > TOKEN_LIMIT )); then
        break
    fi

    tokens_used=$((tokens_used + msg_tokens))
    messages_fit=$((messages_fit + 1))

    # Move to the parent
    current_id=$(jq -r '.parent_id' "$msg_file")
done

# --- Output ---
echo $messages_fit
