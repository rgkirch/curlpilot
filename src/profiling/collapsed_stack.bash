#!/bin/bash
#
# Ingests BASH_ENV and strace logs to produce a collapsed stack file.
# The "weight" of each stack is its total duration in microseconds.
#
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <profile_log_dir> <strace_log_dir>" >&2
    exit 1
fi

PROFILE_LOG_DIR="$1"
STRACE_LOG_DIR="$2"
OUTPUT_FILE="${PROFILE_LOG_DIR}/../collapsed_stack.txt"

echo "Reading BASH logs from: $PROFILE_LOG_DIR" >&2
echo "Reading strace logs from: $STRACE_LOG_DIR" >&2
echo "Writing collapsed stack output to: $OUTPUT_FILE" >&2

# --- Phase 1: Build Process Tree from strace logs ---
declare -A parent_of
declare -A cmd_of

echo "Building process tree from strace logs..." >&2
for f in "$STRACE_LOG_DIR"/trace.*; do
    pid="${f##*.}"

    # Find what command this PID is.
    # The first execve is what defines the process.
    cmd=$(grep -m1 '^execve' "$f" | sed -E 's|execve\("([^"]+)",.*|\1|' | xargs basename || echo "pid-$pid")
    cmd_of["$pid"]="$cmd"

    # Find children of this PID.
    # strace logs forks as: clone(...) = CHILD_PID
    while read -r child_pid; do
        parent_of["$child_pid"]="$pid"
    done < <(grep 'clone(' "$f" | sed -E 's/.* = ([0-9]+)/\1/')
done

# Function to recursively build the process stack for a given PID.
# Caches results in the 'process_stack_cache' array.
declare -A process_stack_cache
function get_process_stack() {
    local pid="$1"
    if [[ -n "${process_stack_cache[$pid]:-}" ]]; then
        echo "${process_stack_cache[$pid]}"
        return
    fi

    local parent=${parent_of[$pid]:-}
    local cmd=${cmd_of[$pid]:-"unknown"}
    local stack=""

    if [[ -n "$parent" ]]; then
        stack="$(get_process_stack "$parent");$cmd"
    else
        stack="$cmd"
    fi
    process_stack_cache["$pid"]="$stack"
    echo "$stack"
}


# --- Phase 2: Process Bash Logs and Aggregate Durations ---
declare -A durations

echo "Processing BASH profile logs..." >&2

# This awk script is the core parser. It reads a profile log, handles
# multi-line commands, and outputs records with duration.
# Output format: PID US DURATION_us US STACK
AWK_SCRIPT='
BEGIN {
    # Unit separator is our field delimiter
    FS = "\x1F";
    # State variables
    prev_time = 0;
    prev_stack = "";
    prev_pid = "";
    cmd_buffer = "";
}

# This pattern matches our metadata lines
# e.g., + US time US ppid US subshell US file US line US stack US RS
/^\+.* \x1E / {
    if (prev_time > 0) {
        # A new record means the previous one is finished.
        # Calculate duration in microseconds.
        duration = sprintf("%.0f", ($2 - prev_time) * 1000000);
        # Print the data for the *previous* command.
        print prev_pid "\x1F" duration "\x1F" prev_stack;
    }

    # Store the metadata for the *current* command.
    prev_time = $2;
    # Get the PID from the log filename
    split(FILENAME, parts, ".");
    prev_pid = parts[1];
    # The function stack is the 6th field.
    prev_stack = $6;

    # Reset command buffer
    cmd_buffer = "";
    next;
}

# Any other line is a continuation of a command.
{
    # We dont actually need the command text for this script,
    # but a real implementation would buffer it.
    # cmd_buffer = cmd_buffer $0 "\n";
}
'

# Find all profile logs, sort them by PID (filename), and process them.
# The output is piped into a Bash loop for final aggregation.
find "$PROFILE_LOG_DIR" -name "*.profile.log" -print0 | sort -z | xargs -0 awk "$AWK_SCRIPT" |
while IFS=$'\x1F' read -r pid duration_us func_stack; do
    if [[ -z "$pid" || -z "$duration_us" || "$duration_us" -le 0 ]]; then
        continue
    fi

    # Get the process stack (e.g., "bats;bash;my_script")
    proc_stack=$(get_process_stack "$pid")

    # The full stack is process stack + function stack.
    # Reverse the function stack for a more natural flamegraph order (main;caller;callee).
    reversed_func_stack=$(echo "$func_stack" | awk '{for(i=NF;i>=1;i--) printf "%s%s", $i, (i==1?"":";")}')
    full_stack="${proc_stack};${reversed_func_stack}"

    # Aggregate the duration.
    durations["$full_stack"]=$(( ${durations[$full_stack]:-0} + duration_us ))
done

# --- Phase 3: Print Collapsed Stack Output ---
echo "Writing final output..." >&2
{
    for stack in "${!durations[@]}"; do
        echo "$stack ${durations[$stack]}"
    done
} > "$OUTPUT_FILE"

echo "Done. Collapsed stack file created at $OUTPUT_FILE" >&2
