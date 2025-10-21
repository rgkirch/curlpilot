#!/bin/bash

# --- Configuration ---
# The directory where your strace log files are located.
# The '*' at the end is a wildcard to select all files in that directory.
LOG_FILES_PATTERN="/tmp/tmp.ULE8Mo2737/strace-logs/*"

# --- Script Logic ---

# Get the filename of this script so we can exclude it from the pipeline.
SELF_NAME=$(basename "$0")

# Find all executable files in the current directory (.), excluding this script itself.
# Store them in a sorted array called 'scripts'.
# The `mapfile` command is a safe way to read lines into an array.
mapfile -t scripts < <(find . -maxdepth 1 -type f -executable -not -name "$SELF_NAME" | sort)

# Check if we found any scripts to run.
if [ ${#scripts[@]} -eq 0 ]; then
    echo "Error: No executable processing scripts found in the current directory." >&2
    echo "Place this script in the same folder as your awk scripts and make them executable (chmod +x your_script.awk)." >&2
    exit 1
fi

# Inform the user which scripts will be run and in what order.
echo "Found ${#scripts[@]} scripts. Processing pipeline will run in this order:"
printf "  -> %s\n" "${scripts[@]}"
echo "---"

# Check if log files exist before trying to process them.
# The `shopt -s nullglob` makes the wildcard expand to nothing if no files match.
shopt -s nullglob
files=($LOG_FILES_PATTERN)
if [ ${#files[@]} -eq 0 ]; then
    echo "Error: No log files found at '$LOG_FILES_PATTERN'" >&2
    exit 1
fi
shopt -u nullglob # Turn nullglob off again

# Use 'cat' to stream all log files into a 'while read' loop.
# This processes the logs line by line.
cat $LOG_FILES_PATTERN | while IFS= read -r original_line; do
    echo "--- [INPUT] ---"
    echo "$original_line"

    # Set the starting point for our pipeline.
    current_line_data="$original_line"

    # Now, loop through our sorted list of scripts.
    for script_path in "${scripts[@]}"; do
        script_filename=$(basename "$script_path")
        echo "--- [AFTER $script_filename] ---"

        # Pipe the current state of the data into the script and capture its output.
        # Using 'printf' is safer than 'echo' for lines that might contain special characters.
        current_line_data=$(printf "%s" "$current_line_data" | "$script_path")

        echo "$current_line_data"
    done

    # Print a clear separator after a full pipeline run for one line is complete.
    echo "========================================================================"
done

echo "--- Pipeline finished ---"
