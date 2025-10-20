# --- Main Block ---
# This block runs for every line from stdin.
{
    # Check if the first field contains the <comm> tag (new strace format: PID<comm>)
    if ($1 ~ /<.*>/) {
        # New parsing for PID<comm> TIME... format

        # Split $1 (e.g., "100<make>") into the PID ("100") and the comm name ("make")
        split($1, a, /[<>]/)
        pid = a[1]
        # Note: a[2] holds the comm name, but we process it below

        # Timestamp is now the second field
        timestamp = $2

    } else {
        # Fallback for old/simple format (PID TIME...)
        pid = $1
        timestamp = $2
    }

    # Now that PID and timestamp are correctly extracted, we must re-process the line content.

    # 1. Strip the PID and TIME so line_content starts with the syscall.
    line_content = $0

    # We strip based on whether the <comm> tag exists in $1 or not.
    if ($1 ~ /<.*>/) {
        # Strip: "PID<comm> TIME "
        sub(/^[0-9]+<[^>]+>\s+[0-9\.]+\s+/, "", line_content)
    } else {
        # Strip: "PID TIME "
        sub(/^[0-9]+\s+[0-9\.]+\s+/, "", line_content)
    }

    # 2. Capture and process <comm> if present. This logic is used for early naming of threads.
    # We still check the original $0 because the comm tag might be on the RHS of clone()
    if (match($0, /<([^>]+)>(\s+)?$/, m_comm)) {
        comm_name = m_comm[1]

        # If the 'cmd' hasn't been set by execve yet, use the 'comm' as an early placeholder name.
        if (pids[pid]["cmd"] == "") {
            pids[pid]["cmd"] = comm_name
        }
    }

    # 3. Match process creation (clone/fork/vfork)
    if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)/, m)) {
        parent_pid = pid
        child_pid = m[2]
        if (child_pid > 0) {
            children[parent_pid][child_pid] = 1
            pids[child_pid]["parent_pid"] = parent_pid
        }
    }
    # Special clone case where pid is appended with <comm> on the RHS
    if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)<[^>]+>/, m_clone)) {
        parent_pid = pid
        child_pid = m_clone[2]
        if (child_pid > 0) {
            children[parent_pid][child_pid] = 1
            pids[child_pid]["parent_pid"] = parent_pid
        }
    }


    # 4. Match process execution (execve) - This logic is the canonical source for command name
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

        # Apply shell script heuristic
        if (basename_exe ~ /^(bash|sh)$/ && args[2] != "") {
            basename_arg1 = args[2]
            gsub(/.*\//, "", basename_arg1)
            pids[pid]["cmd"] = basename_arg1
        } else {
            pids[pid]["cmd"] = basename_exe
        }
    }

    # 5. Match process exit
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

# --- Helper Functions (No change needed) ---
function get_stack(pid,   stack_str, current_pid, parent_pid, cmd_name, default_name) {
    # Recursively walks up the parent tree to build the collapsed stack string.
    stack_str = ""
    current_pid = pid
    while (current_pid in pids) {
        # Check if the command name exists.
        cmd_name = pids[current_pid]["cmd"]

        if (cmd_name == "") {
            # --- Fallback logic to fix 'unknown' ---

            # If command name is missing, attempt to inherit from the parent
            parent_pid = pids[current_pid]["parent_pid"]
            if (parent_pid in pids && pids[parent_pid]["cmd"] != "") {
                cmd_name = pids[parent_pid]["cmd"]
            }

            # If still no command name, use a traceable placeholder and log the event
            if (cmd_name == "") {
                default_name = "-NO_EXECVE-" current_pid
                # Log the fallback event to stderr to avoid breaking unit tests on stdout
                print "⚠️ WARNING: PID " current_pid " command name missing. Falling back to '" default_name "'." | "cat 1>&2"
                cmd_name = default_name
            }

            # --- End of Fallback logic ---
        }

        # Original logic: If it passed the checks above but was still empty, use "unknown"
        cmd_name = cmd_name ? cmd_name : "unknown"

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


# --- END Block (No change needed) ---
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
