# This AWK script processes a set of strace -ff logs to produce a
# collapsed stack file representing the process hierarchy and duration.

# --- Global Data Structures ---
# pids[pid]["parent_pid"]   = The parent PID of this process
# pids[pid]["cmd"]          = The command name (basename)
# pids[pid]["start_time"]   = The timestamp of the execve call
# pids[pid]["end_time"]     = The timestamp of the exit_group call
# pids[pid]["total_dur"]    = Calculated total duration (end - start)
# pids[pid]["self_dur"]     = Calculated self-duration (total - children)
# children[pid][child_pid] = An array holding the PIDs of children for a given parent

# --- Main Block ---
# This block runs for every line in every input file.
{
    pid = get_pid_from_filename(FILENAME)
    timestamp = $1

    # Match process creation (clone/fork) to build the parent-child tree.
    if ($2 ~ /^(clone|fork|vfork)/) {
        parent_pid = pid
        child_pid = $NF

        if (child_pid > 0) {
            children[parent_pid][child_pid] = 1
            pids[child_pid]["parent_pid"] = parent_pid
        }
    }

    # Match process execution (execve). This gives us the command name and a more accurate start time.
    if (match($0, /execve\("([^"]+)", \[(.+)\]/, m)) {
        pids[pid]["start_time"] = timestamp

        executable_path = m[1]
        args_str = m[2]

        # Split the argument string into an array.
        split(args_str, args, /, /)

        # Clean up the arguments by removing quotes.
        for (i in args) {
            gsub(/^"|"$/, "", args[i])
        }

        basename_exe = executable_path
        gsub(/.*\//, "", basename_exe)

        # --- NEW LOGIC: Get better names ---
        # If the executable is a shell, the real name is likely the script in argv[1].
        if (basename_exe ~ /^(bash|sh)$/ && args[2] != "") {
            basename_arg1 = args[2]
            gsub(/.*\//, "", basename_arg1)
            pids[pid]["cmd"] = basename_arg1
        } else {
            # Otherwise, just use the executable's basename.
            pids[pid]["cmd"] = basename_exe
        }
        # --- END NEW LOGIC ---
    }

    # Match process exit to get the end time.
    if ($2 ~ /^exit_group/ || $2 == "+++") {
        # Use the first timestamp encountered for exit (preferring exit_group).
        if (pids[pid]["end_time"] == 0) {
            pids[pid]["end_time"] = timestamp
        }
    }
}

# --- Helper Functions ---
function get_pid_from_filename(filename) {
    # Extracts the PID from a filename like "trace.12345"
    sub(/.*\.|\.log$/, "", filename)
    return filename
}

function get_stack(pid,   stack_str, current_pid) {
    # Recursively walks up the parent tree to build the collapsed stack string.
    stack_str = ""
    current_pid = pid
    while (current_pid in pids) {
        # Prepend the command name to the stack string.
        cmd_name = pids[current_pid]["cmd"] ? pids[current_pid]["cmd"] : "unknown"
        if (stack_str == "") {
            stack_str = cmd_name
        } else {
            stack_str = cmd_name ";" stack_str
        }

        # Move up to the parent.
        if (pids[current_pid]["parent_pid"] in pids) {
            current_pid = pids[current_pid]["parent_pid"]
        } else {
            break # Reached the top of our traced tree
        }
    }
    return stack_str
}


# --- END Block ---
# This block runs once after all lines from all files have been processed.
END {
    # --- Pass 1: Calculate Total Durations ---
    for (pid in pids) {
        if (pids[pid]["start_time"] > 0 && pids[pid]["end_time"] > 0) {
            pids[pid]["total_dur"] = pids[pid]["end_time"] - pids[pid]["start_time"]
            pids[pid]["self_dur"] = pids[pid]["total_dur"] # Initialize self_dur
        }
    }

    # --- Pass 2: Calculate Self Durations ---
    # Subtract the total time of children from their parent's self-time.
    for (parent_pid in children) {
        for (child_pid in children[parent_pid]) {
            if ((parent_pid in pids) && (child_pid in pids) && (pids[child_pid]["total_dur"] > 0)) {
                pids[parent_pid]["self_dur"] -= pids[child_pid]["total_dur"]
            }
        }
    }

    # --- Pass 3: Generate Collapsed Stack Output ---
    # Create a temporary array to hold lines for sorting.
    OFS=""
    num_lines = 0
    for (pid in pids) {
        # We only care about processes that did some work.
        if (pids[pid]["self_dur"] > 0) {
            stack = get_stack(pid)
            # Convert duration to integer milliseconds for the weight.
            weight = int(pids[pid]["self_dur"] * 1000)
            if (weight > 0) {
                lines[++num_lines] = stack " " weight
            }
        }
    }

    # Sort the lines alphabetically for stable output.
    asort(lines)

    # Print the final sorted output.
    for (i = 1; i <= num_lines; i++) {
        print lines[i]
    }
}
