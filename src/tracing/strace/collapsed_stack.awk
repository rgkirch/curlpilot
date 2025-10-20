# This AWK script processes a stream of strace logs to produce a
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
# This block runs for every line from stdin.
{
    pid = $1
    timestamp = $2

    # Get the rest of the line after PID and timestamp for matching.
    line_content = $0
    sub(/^[0-9]+\s+[0-9\.]+\s+/, "", line_content)

    # Match process creation (clone/fork/vfork)
    if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)/, m)) {
        parent_pid = pid
        child_pid = m[2]
        if (child_pid > 0) {
            children[parent_pid][child_pid] = 1
            pids[child_pid]["parent_pid"] = parent_pid
        }
    }

    # Match process execution (execve)
    if (match(line_content, /^execve\("([^"]+)", \[(.+)\]/, m)) {
        pids[pid]["start_time"] = timestamp

        executable_path = m[1]
        args_str = m[2]

        split(args_str, args, /, /)

        for (i in args) {
            gsub(/^"|"$/, "", args[i])
        }

        basename_exe = executable_path
        gsub(/.*\//, "", basename_exe)

        if (basename_exe ~ /^(bash|sh)$/ && args[2] != "") {
            basename_arg1 = args[2]
            gsub(/.*\//, "", basename_arg1)
            pids[pid]["cmd"] = basename_arg1
        } else {
            pids[pid]["cmd"] = basename_exe
        }
    }

    # Match process exit
    if (match(line_content, /^exit_group/)) {
        if (pids[pid]["end_time"] == 0) {
            pids[pid]["end_time"] = timestamp
        }
    }
    if (match(line_content, /^\+\+\+ exited/)) {
         if (pids[pid]["end_time"] == 0) {
            pids[pid]["end_time"] = timestamp
        }
    }
}

# --- Helper Functions ---
function get_stack(pid,   stack_str, current_pid) {
    # Recursively walks up the parent tree to build the collapsed stack string.
    stack_str = ""
    current_pid = pid
    while (current_pid in pids) {
        cmd_name = pids[current_pid]["cmd"] ? pids[current_pid]["cmd"] : "unknown"
        if (stack_str == "") {
            stack_str = cmd_name
        } else {
            stack_str = cmd_name ";" stack_str
        }

        if (pids[current_pid]["parent_pid"] in pids) {
            current_pid = pids[current_pid]["parent_pid"]
        } else {
            break
        }
    }
    return stack_str
}


# --- END Block ---
END {
    # Pass 1: Calculate Total Durations
    for (pid in pids) {
        if (pids[pid]["start_time"] > 0 && pids[pid]["end_time"] > 0) {
            pids[pid]["total_dur"] = pids[pid]["end_time"] - pids[pid]["start_time"]
            pids[pid]["self_dur"] = pids[pid]["total_dur"]
        }
    }

    # Pass 2: Calculate Self Durations
    for (parent_pid in children) {
        for (child_pid in children[parent_pid]) {
            if ((parent_pid in pids) && (child_pid in pids) && (pids[child_pid]["total_dur"] > 0)) {
                pids[parent_pid]["self_dur"] -= pids[child_pid]["total_dur"]
            }
        }
    }

    # Pass 3: Generate Collapsed Stack Output
    num_lines = 0
    for (pid in pids) {
        if (pids[pid]["self_dur"] > 0) {
            stack = get_stack(pid)
            weight = int(pids[pid]["self_dur"] * 1000)
            if (weight > 0) {
                lines[++num_lines] = stack " " weight
            }
        }
    }

    asort(lines)

    for (i = 1; i <= num_lines; i++) {
        print lines[i]
    }
}
