#!/bin/bash

# This script checks for required dependencies defined in dependencies.json.
# It handles both executable commands and executable setup scripts.

# curlpilot/check_deps.sh

SCRIPT_DIR="$(dirname "$0")"
DEPENDENCIES_FILE="$SCRIPT_DIR/dependencies.json"

# Check if dependencies.json exists
if [ ! -f "$DEPENDENCIES_FILE" ]; then
    echo "Error: dependencies.json not found at $DEPENDENCIES_FILE" >&2
    exit 1
fi

# Ensure jq is installed for this script to work
if ! command -v "jq" >/dev/null 2>&1; then
    echo "Error: 'jq' command not found. It is required to parse dependencies.json. Please install it." >&2
    exit 1
fi

SILENT_SUCCESS=false
for arg in "$@"; do
    if [ "$arg" == "--silent-success" ]; then
        SILENT_SUCCESS=true
        break
    fi
done

MISSING_DEPS=""

# First, check for all required executable commands
for dep in $(jq -c '.[] | select(.type == "executable")' "$DEPENDENCIES_FILE"); do
    name=$(echo "$dep" | jq -r '.name')
    if ! command -v "$name" >/dev/null 2>&1; then
        if [ -z "$MISSING_DEPS" ]; then
            MISSING_DEPS="$name"
        else
            MISSING_DEPS="$MISSING_DEPS, $name"
        fi
    fi
done

# If any executables are missing, exit now before running scripts
if [ -n "$MISSING_DEPS" ]; then
    echo "Error: The following required command(s) not found: $MISSING_DEPS. Please install them." >&2
    exit 1
fi

# Second, execute all dependency scripts
for dep in $(jq -c '.[] | select(.type == "script")' "$DEPENDENCIES_FILE"); do
    name=$(echo "$dep" | jq -r '.name')
    script_path="$SCRIPT_DIR/scripts/$name"

    if [ -f "$script_path" ]; then
        echo "--- Running dependency script: $name ---"
        if ! bash "$script_path"; then
            echo "Error: Dependency script '$name' failed to execute." >&2
            exit 1
        fi
        echo "--- Finished dependency script: $name ---"
    else
        echo "Error: Dependency script not found at '$script_path'" >&2
        exit 1
    fi
done

if [ "$SILENT_SUCCESS" = false ]; then
    echo "All required dependencies found and scripts executed successfully."
fi
exit 0
