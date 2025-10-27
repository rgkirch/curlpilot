#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Check if an argument was passed.
if [ -n "$1" ]; then
    # Use the argument as the file pattern
    LOG_FILES_PATTERN="$1"
else
    # No argument, fall back to the default config file
    echo "No log source provided, using default from log_dir.bash..." >&2
    source "$SCRIPT_DIR/log_dir.bash"
fi

echo "Starting data generation pipeline..." >&2

# Find all executable awk scripts
mapfile -t scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -executable -name '[0-9][0-9][0-9]_*.awk' | sort -V)

# Check if we found any scripts to run.
if [ ${#scripts[@]} -eq 0 ]; then
    echo "Error: No executable awk scripts (e.g., 00_*.awk) found in '$SCRIPT_DIR'." >&2
    exit 1
fi
# Check if log files exist
shopt -s nullglob
files=($LOG_FILES_PATTERN) # This now uses the variable we set above
if [ ${#files[@]} -eq 0 ]; then
    # Special case: /dev/stdin is a valid file but nullglob won't expand it
    if [ "$LOG_FILES_PATTERN" != "/dev/stdin" ]; then
        echo "Error: No log files found at '$LOG_FILES_PATTERN'" >&2
        exit 1
    fi
fi
shopt -u nullglob

# Build the full pipeline command
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
