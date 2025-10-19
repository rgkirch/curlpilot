#!/usr/bin/gawk -f
#
# This awk script processes `strace -ff` log files to generate a collapsed
# stack file representing process wall-clock duration.
#

# This block runs before processing any files.
# It defines a helper function to extract the PID from a filename.
function get_pid_from_filename(filename) {
    # basename, then remove "trace." prefix
    sub(/.*\//, "", filename)
    sub(/trace\./, "", filename)
    return filename + 0 # Convert to number
}

# This block runs for every line of every file.
{
    pid = get_pid_from_filename(FILENAME)
    timestamp = $1

    # Match process creation (clone/fork/vfork). This establishes the parent-child link.
    if (match($0, /(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)/, m)) {
        child_pid = m[2]
        pids[child_pid]["ppid"] = pid
        pids[pid]["children"][child_pid] = 1 # Store children for self-time calculation
        pids[child_pid]["start_time"] = timestamp # Tentative start time is creation time
    }

    # Match process execution (execve). This gives us the command name and a more accurate start time.
    if (match($0, /execve\("([^"]+)"/, m)) {
        pids[pid]["start_time"] = timestamp
        cmd_path = m[1]
        gsub(/.*\//, "", cmd_path) # Get basename
        pids[pid]["name"] = cmd_path
    }

    # Match process exit to get the end time.
    if ($2 == "exit_group" || $1 == "+++") {
        # Use the latest timestamp for exit, in case of multiple exit-related lines.
        if (timestamp > pids[pid]["end_time"]) {
            pids[pid]["end_time"] = timestamp
        }
    }
}

# This block runs after all files have been processed.
END {
    # Pass 1: Calculate total duration for every process.
    for (pid in pids) {
        if (pids[pid]["start_time"] && pids[pid]["end_time"]) {
            pids[pid]["total_duration"] = pids[pid]["end_time"] - pids[pid]["start_time"]
        }
    }

    # Pass 2: Calculate self-duration for every process.
    for (pid in pids) {
        if (pids[pid]["total_duration"]) {
            self_duration = pids[pid]["total_duration"]
            for (child_pid in pids[pid]["children"]) {
                if (pids[child_pid]["total_duration"]) {
                    # Ensure child time is within parent time to avoid timing skew.
                    if (pids[child_pid]["start_time"] < pids[pid]["end_time"]) {
                       self_duration -= pids[child_pid]["total_duration"]
                    }
                }
            }
            # Prevent negative durations.
            pids[pid]["self_duration"] = (self_duration > 0) ? self_duration : 0
        }
    }

    # Pass 3: Reconstruct stacks and print the final output.
    for (pid in pids) {
        # Only print a line for processes that did some work and have a name.
        if (pids[pid]["self_duration"] > 0 && pids[pid]["name"]) {
            current_pid = pid
            stack = pids[current_pid]["name"]
            # Walk up the parent chain to build the full stack trace.
            while (pids[current_pid]["ppid"] in pids) {
                current_pid = pids[current_pid]["ppid"]
                # Use a generic name if the parent existed but we couldnt parse a name for it.
                parent_name = pids[current_pid]["name"] ? pids[current_pid]["name"] : "PID:" current_pid
                stack = parent_name ";" stack
            }

            # Convert self-duration to integer milliseconds for the weight.
            weight = int(pids[pid]["self_duration"] * 1000)
            if (weight > 0) {
                 print stack " " weight
            }
        }
    }
}
