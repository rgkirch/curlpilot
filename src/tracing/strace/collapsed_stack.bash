#!/bin/bash
#
# This script finds all 'trace.*' files in the given directories,
# concatenates their content, SORTS IT BY TIMESTAMP, and pipes
# the result to the awk script.
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
# It uses 'find -exec cat {} +' for efficiency instead of a while-read loop.
process_logs() {
    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            echo "Warning: Directory not found at '$dir'. Skipping." >&2
            continue
        fi

        # Find all trace files and efficiently cat their contents to stdout.
        find "$dir" -name 'trace.*' -exec cat {} +
    done
}

process_logs "$@" | sort -k2,2n | gawk -f "$AWK_SCRIPT_PATH"
