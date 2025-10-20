# This AWK script processes a stream of strace logs to produce a
# collapsed stack file representing the process hierarchy and duration.

# --- Global Data Structures ---
# pids[pid]["parent_pid"]      = The parent PID of this process
# pids[pid]["cmd"]             = The command name (basename from execve OR comm fallback)
# pids[pid]["start_time"]      = The timestamp of the execve call
# pids[pid]["end_time"]        = The timestamp of the exit_group call
# pids[pid]["had_execve"]      = Flag (1) if this process called execve.
# pids[pid]["total_dur"]       = Calculated total duration (end - start)
# pids[pid]["self_dur"]        = Calculated self-duration (total - children)
# children[pid][child_pid]   = An array holding the PIDs of children for a given parent
# aggregated_stacks[stack]   = Associative array to sum weights for identical stacks

# --- Main Block ---
# This block runs for every line from stdin.
{
    # We rely on AWK's field splitting, assuming one or more spaces/tabs separate fields.
    pid = $1
    timestamp = $2
    comm_name = "" # Will be captured from PID<comm>

    # 1. PID and TIME extraction based on format
    if ($1 ~ /<.*>/) {
        # Format: PID<comm> TIME...
        split($1, a, /[<>]/)
        pid = a[1]
        comm_name = a[2] # <-- CORRECTED CAPTURE
        timestamp = $2
        line_content = $0
        sub(/^[0-9]+<[^>]+>\s+[0-9\.]+\s+/, "", line_content)
    } else {
        # Fallback format (Unit Tests, simpler logs)
        pid = $1
        timestamp = $2
        line_content = $0
        sub(/^[0-9]+\s+[0-9\.]+\s+/, "", line_content)
    }

    # 2. Set fallback command name (if we don't have one) from <comm>
    if (comm_name != "" && pids[pid]["cmd"] == "") {
        pids[pid]["cmd"] = comm_name
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
    # Special clone case where pid is appended with <comm> on the RHS (e.g., in a clone call)
    if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)<[^>]+>/, m_clone)) {
        parent_pid = pid
        child_pid = m_clone[2]
        if (child_pid > 0) {
            children[parent_pid][child_pid] = 1
            pids[child_pid]["parent_pid"] = parent_pid
        }
    }


    # 4. Match process execution (execve) - This is the canonical source
    if (match(line_content, /^execve\("([^"]+)", \[(.+)\]/, m)) {
        pids[pid]["had_execve"] = 1 # <--- THE CRITICAL FLAG
        pids[pid]["start_time"] = timestamp

        executable_path = m[1]
        args_str = m[2]

        split(args_str, args, /, /)

        for (i in args) {
            gsub(/^"|"$/, "", args[i])
        }

        basename_exe = executable_path
        gsub(/.*\//, "", basename_exe)

        # --- CORRECTED SHELL HEURISTIC (THE FIX FOR '-c') ---
        # Apply shell script heuristic
        # Check if it's a shell, arg[2] exists, AND arg[2] does not start with "-"
        if (basename_exe ~ /^(bash|sh|zsh|dash)$/ && args[2] != "" && substr(args[2], 1, 1) != "-") {
            # It's 'bash script.sh ...', so use the script name
            basename_arg1 = args[2]
            gsub(/.*\//, "", basename_arg1)
            pids[pid]["cmd"] = basename_arg1
        } else {
            # It's a non-shell (e.g., 'cat'), or 'bash -c', or 'bash -l', etc.
            # In all these cases, the executable's basename is correct.
            pids[pid]["cmd"] = basename_exe
        }
    }

    # 5. Match process exit
    if (match(line_content, /^exit_group/) || match(line_content, /^\+\+\+ exited/)) {
        if (pids[pid]["end_time"] == 0) {
            pids[pid]["end_time"] = timestamp
        }
    }
}

# ----------------------------------------------------------------------------------

# --- Helper Functions ---
function get_stack(pid,     stack_str, current_pid, parent_pid, cmd_name, default_name, had_execve) {
    # Recursively walks up the parent tree to build the collapsed stack string.
    stack_str = ""
    current_pid = pid
    while (current_pid in pids) {
        cmd_name = pids[current_pid]["cmd"]
        had_execve = pids[current_pid]["had_execve"]

        # --- Fallback Logic Block (Unchanged) ---
        if (cmd_name == "") {
            parent_pid = pids[current_pid]["parent_pid"]
            if (parent_pid in pids && pids[parent_pid]["cmd"] != "") {
                cmd_name = pids[parent_pid]["cmd"]
            }

            if (cmd_name == "") {
                default_name = "-NO_EXECVE-" current_pid
                print "⚠️ WARNING: PID " current_pid " command name missing. Falling back to '" default_name "'." | "cat 1>&2"
                cmd_name = default_name
            }
        }
        # ----------------------------------------

        # --- CORRECTED FILTERING LOGIC (The Fix for 'bash' noise) ---
        # If the command name is a generic shell AND it NEVER called execve,
        # then it must be a noisy, transient helper thread we should skip.
        if (cmd_name ~ /^(bash|sh|zsh|dash)$/ && had_execve != 1) {
            # Only skip it if it's not the root process (which might be the entry point).
            if (pids[current_pid]["parent_pid"] != "") {
                current_pid = pids[current_pid]["parent_pid"]
                continue # Skip this helper frame, move up.
            }
        }

        # --- Stack Assembly ---
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

# ----------------------------------------------------------------------------------

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

    # --- CORRECTED AGGREGATION (THE FIX FOR DUPLICATES) ---

    # Pass 3: Aggregate Stacks and Generate Output
    # Use an associative array to sum weights for identical stacks
    for (pid in pids) {
        if (pids[pid]["self_dur"] > 0) {
            stack = get_stack(pid)
            weight = int(pids[pid]["self_dur"] * 1000) # Convert seconds to ms
            if (weight > 0) {
                # This automatically sums weights for the same stack string
                aggregated_stacks[stack] += weight
            }
        }
    }

    # Set the sort order to be by stack string (alphabetical)
    PROCINFO["sorted_in"] = "@ind_str_asc"

    # Print the final, aggregated, and sorted lines
    for (stack in aggregated_stacks) {
        print stack " " aggregated_stacks[stack]
    }
}
