#!/bin/bash
#
# This script is a wrapper that finds strace log files and passes them
# to the awk processing script for analysis.
#

set -euo pipefail

# --- Validation ---
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <path-to-strace-logs-directory>" >&2
    exit 1
fi

STRACE_LOG_DIR="$1"

if [[ ! -d "$STRACE_LOG_DIR" ]]; then
    echo "Error: Directory not found at '$STRACE_LOG_DIR'" >&2
    exit 1
fi
# --- End Validation ---


# --- File Gathering ---
# Find all trace files.
TRACE_FILES=()
while IFS= read -r -d '' file; do
    TRACE_FILES+=("$file")
done < <(find "$STRACE_LOG_DIR" -name 'trace.*' -print0)

if [[ ${#TRACE_FILES[@]} -eq 0 ]]; then
    echo "Warning: No 'trace.*' files found in '$STRACE_LOG_DIR'" >&2
    exit 0
fi
# --- End File Gathering ---


# --- Processing ---
# Get the directory containing this script to reliably find the .awk file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_SCRIPT_PATH="$SCRIPT_DIR/collapsed_stack.awk"

if [[ ! -f "$AWK_SCRIPT_PATH" ]]; then
    echo "Error: Awk processor not found at '$AWK_SCRIPT_PATH'" >&2
    exit 1
fi

# Execute the awk script, passing all found trace files to it.
gawk -f "$AWK_SCRIPT_PATH" "${TRACE_FILES[@]}"
