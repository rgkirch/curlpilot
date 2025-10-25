#!/bin/bash

# --- Configuration ---
# The directory where your strace log files are located.
source ./log_dir.bash
# The directory where your processing scripts are located.
SCRIPT_DIR="."

# --- Script Logic ---

echo "Starting data generation pipeline..." >&2

# Find all executable awk scripts in the specified directory, sorted numerically.
# The `sort -V` command handles version-style numbering (e.g., 2 is before 10).
mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -executable -name '[0-9][0-9][0-9]_*.awk' | sort -V)

# Check if we found any scripts to run.
if [ ${#scripts[@]} -eq 0 ]; then
    echo "Error: No executable awk scripts (e.g., 00_*.awk) found in '$SCRIPT_DIR'." >&2
    exit 1
fi

echo "Found ${#scripts[@]} scripts. Pipeline will be:" >&2
printf "  -> %s\n" "${scripts[@]}" >&2

# Check if log files exist before trying to process them.
shopt -s nullglob
files=($LOG_FILES_PATTERN)
if [ ${#files[@]} -eq 0 ]; then
    echo "Error: No log files found at '$LOG_FILES_PATTERN'" >&2
    exit 1
fi
shopt -u nullglob

# Build the full pipeline command as a single string.
pipeline_cmd="cat $LOG_FILES_PATTERN"
for script in "${scripts[@]}"; do
    pipeline_cmd+=" | \"$script\""
done

# Execute the final composed pipeline.
# The output will be a stream of JSON objects from your various awk scripts.
# You can redirect this output to a file, e.g., by running:
# ./generate_flamegraph_data.sh > flamegraph_events.json
echo "---" >&2
echo "Running pipeline... Output will follow." >&2
echo "---" >&2

eval "$pipeline_cmd"

echo "---" >&2
echo "Pipeline finished." >&2
