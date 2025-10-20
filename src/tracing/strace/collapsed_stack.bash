#!/bin/bash
#
# This script finds all 'trace.*' files in the given directories,
# concatenates their content, and pipes the result to the awk script.
#
set -euo pipefail

# --- Validation ---
if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 <path-to-strace-logs-directory>..." >&2
    exit 1
fi

# --- Processing ---
# Get the directory containing this script to reliably find the .awk file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_SCRIPT_PATH="$SCRIPT_DIR/collapsed_stack.awk"

if [[ ! -f "$AWK_SCRIPT_PATH" ]]; then
    echo "Error: Awk processor not found at '$AWK_SCRIPT_PATH'" >&2
    exit 1
fi

# This function processes all directories passed as arguments.
process_logs() {
    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            echo "Warning: Directory not found at '$dir'. Skipping." >&2
            continue
        fi

        # Find all trace files, and for each one, pipe the content directly.
        find "$dir" -name 'trace.*' -print0 | while IFS= read -r -d '' file; do
            cat "$file" # Pipe the file content directly.
        done
    done
}

# Pipe the processed log stream into the awk script for analysis.
process_logs "$@" | gawk -f "$AWK_SCRIPT_PATH"
