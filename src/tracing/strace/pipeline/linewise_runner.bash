#!/bin/bash

# --- Configuration ---
# The directory where your strace log files are located.
source ./log_dir.bash
# The directory where your processing scripts are located.
SCRIPT_DIR="."

# --- Script Logic ---

echo "Starting line-wise data pipeline..."

# Find all executable awk scripts in the specified directory, sorted numerically.
# The `sort -V` command handles version-style numbering (e.g., 2 is before 10).
mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -executable -name '[0-9][0-9]_*.awk' | sort -V)

# Check if we found any scripts to run.
if [ ${#scripts[@]} -eq 0 ]; then
    echo "Error: No executable awk scripts (e.g., 00_*.awk) found in '$SCRIPT_DIR'." >&2
    exit 1
fi

echo "Found ${#scripts[@]} scripts. Pipeline will be:"
printf "  -> %s\n" "${scripts[@]}"

# Check if log files exist before trying to process them.
shopt -s nullglob
files=($LOG_FILES_PATTERN)
if [ ${#files[@]} -eq 0 ]; then
    echo "Error: No log files found at '$LOG_FILES_PATTERN'" >&2
    exit 1
fi
shopt -u nullglob

echo "---"
echo "Running pipeline... Output will follow."
echo "---"

# Use 'cat' to stream all log files into a 'while read' loop.
# This processes the logs line by line.
cat "${files[@]}" | while IFS= read -r original_line; do
    current_line_data="$original_line"

    # Pass this single line through the entire pipeline, script by script.
    for script_path in "${scripts[@]}"; do
        # Use printf for safety, pipe it into the script, and capture the stdout.
        # Any debug prints to stderr (e.g., print "..." > "/dev/stderr")
        # will print to the console immediately, in order.
        current_line_data=$(printf "%s" "$current_line_data" | "$script_path")
    done

    # After the line has passed through all scripts, print the final result.
    # We only print if the final result is not an empty string.
    if [ -n "$current_line_data" ]; then
        echo "$current_line_data"
    fi
done

echo "---"
echo "Line-wise pipeline finished."
