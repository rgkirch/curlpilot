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

# The output will be a stream of JSON objects from your various awk scripts.
# You can redirect this output to a file, e.g., by running:
# ./generate_flamegraph_data.sh > flamegraph_events.json
echo "---" >&2
echo "Running pipeline... Output will follow." >&2
echo "---" >&2

export AWKPATH="$SCRIPT_DIR/lib"

# Execute the hard-coded pipeline
cat $LOG_FILES_PATTERN |
    "$SCRIPT_DIR/101_add_unit_separator.awk" |
    "$SCRIPT_DIR/125_wait.awk" |
    "$SCRIPT_DIR/130_signal.awk" |
    "$SCRIPT_DIR/135_interrupted_call.awk" |
    "$SCRIPT_DIR/145_esrch_error.awk" |
    "$SCRIPT_DIR/190_json.awk"

echo "---" >&2
echo "Pipeline finished." >&2
