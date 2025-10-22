#!/bin/bash

# --- Configuration ---
# The directory where your strace log files are located.
LOG_FILES_PATTERN="/tmp/tmp.ULE8Mo2737/strace-logs/*"

# --- Script Logic ---

# The arguments passed to this script are the scripts whose output we want to debug.
# We store their basenames in an array for easy checking.
scripts_to_debug=()
for arg in "$@"; do
    scripts_to_debug+=("$(basename "$arg")")
done

# Get the filename of this script so we can exclude it from the pipeline.
SELF_NAME=$(basename "$0")

# Find all executable files in the current directory (.), excluding this script itself.
# Store them in a sorted array called 'scripts'.
mapfile -d $'\0' -t all_scripts < <(find . -maxdepth 1 -type f -executable -name '*.awk' -print0 | sort --zero-terminated)

# Check if we found any scripts to run.
if [ ${#all_scripts[@]} -eq 0 ]; then
    echo "Error: No executable processing scripts found in the current directory." >&2
    echo "Place this script in the same folder as your awk scripts and make them executable (chmod +x your_script.awk)." >&2
    exit 1
fi

# Inform the user about the setup.
echo "Found ${#all_scripts[@]} scripts to run in the pipeline:"
printf "  -> %s\n" "${all_scripts[@]}"
if [ ${#scripts_to_debug[@]} -gt 0 ]; then
    echo "Debugging output will be shown for:"
    printf "  -> %s\n" "${scripts_to_debug[@]}"
fi
echo "---"

# Check if log files exist before trying to process them.
shopt -s nullglob
files=($LOG_FILES_PATTERN)
if [ ${#files[@]} -eq 0 ]; then
    echo "Error: No log files found at '$LOG_FILES_PATTERN'" >&2
    exit 1
fi
shopt -u nullglob

# Helper function to check if an item is in an array
is_in_array() {
    local needle=$1
    shift
    for item; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Use 'cat' to stream all log files into a 'while read' loop.
cat "${files[@]}" | while IFS= read -r original_line; do
    # This flag will track if any debug output was generated for this original_line.
    printed_debug_for_this_line=false
    current_line_data="$original_line"

    # Loop through all discovered scripts.
    for script_path in "${all_scripts[@]}"; do
        script_filename=$(basename "$script_path")

        # Pipe the current data into the script and capture its output.
        current_line_data=$(printf "%s" "$current_line_data" | "$script_path")

        # If the current script is in our debug list AND its output is not empty, print it.
        if is_in_array "$script_filename" "${scripts_to_debug[@]}" && [ -n "$current_line_data" ]; then
            echo "--- [DEBUG: AFTER $script_filename] ---"
            echo "$current_line_data"
            printed_debug_for_this_line=true
        fi
    done

    # Only print the separator if we actually printed some debug info for this line.
    if [ "$printed_debug_for_this_line" = true ]; then
        echo "========================================================================"
    fi
done

echo "--- Pipeline finished ---"
