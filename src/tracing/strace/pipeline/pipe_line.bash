#!/bin/bash
set -euo pipefail

# --- Configuration ---
# Get the absolute path to this script, resolving any symlinks.
SCRIPT_PATH=$(readlink -f "$0")
# Get the directory where this script itself is located.
# This is a robust way to find the script's location, even when called by GNU Parallel.
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# --- Script Logic ---

# Find all executable awk scripts in the specified directory, sorted numerically.
# The `sort -V` command handles version-style numbering (e.g., 2 is before 10).
# We run this discovery logic *once* inside the script.
mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -executable -name '[0-9][0-9]_*.awk' | sort -V)

# Check if we found any scripts to run.
if [ ${#scripts[@]} -eq 0 ]; then
    # Print to stderr so parallel can capture it
    echo "Error: No executable awk scripts (e.g., 00_*.awk) found in '$SCRIPT_DIR'." >&2
    exit 1
fi

# This script is now a "worker" that processes one line from stdin.
# The 'while' loop has been removed; GNU Parallel will handle the looping.
IFS= read -r original_line

current_line_data="$original_line"

# Pass this single line through the entire pipeline, script by script.
for script_path in "${scripts[@]}"; do
    # Use printf for safety, pipe it into the script, and capture the stdout.
    # Any debug prints to stderr (e.g., print "..." > "/dev/stderr")
    # will be printed to this script's stderr.
    current_line_data=$(printf "%s" "$current_line_data" | "$script_path")
done

# After the line has passed through all scripts, print the final result.
# We only print if the final result is not an empty string.
if [ -n "$current_line_data" ]; then
    echo "$current_line_data"
fi
