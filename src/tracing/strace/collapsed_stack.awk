# This AWK script processes a stream of strace logs to produce a
# collapsed stack file representing the process hierarchy and duration.

# --- Global Data Structures ---
# pids[pid]["parent_pid"]      = The parent PID of this process
# pids[pid]["cmd"]             = The command name (basename from execve OR comm fallback)
# pids[pid]["start_time"]      = The timestamp (from clone OR execve)
# pids[pid]["end_time"]        = The timestamp of the exit_group call
# pids[pid]["had_execve"]      = Flag (1) if this process called execve.
# pids[pid]["total_dur"]       = Calculated total duration (end - start)
# pids[pid]["self_dur"]        = Calculated self-duration (total - children)
# children[pid][child_pid]   = An array holding the PIDs of children for a given parent
# aggregated_stacks[stack]   = Associative array to sum weights for identical stacks

# --- Main Block (Dispatcher) ---
{
    # --- 1. Universal Line Parsing ---
    # We only process lines in the "PID<comm> TIME..." format.
    if ($1 !~ /<.*>/) {
        # This skips junk lines like "--- SIGCHLD {si_signo=...} ---"
        # or mis-formatted unit test data.
        next
    }

    # Format: PID<comm> TIME...
    split($1, a, /[<>]/)
    pid = a[1]
    comm_name = a[2]
    timestamp = $2
    line_content = $0
    sub(/^[0-9]+<[^>]+>\s+[0-9\.]+\s+/, "", line_content)

    # --- 2. Set Fallback Command Name (from <comm>) ---
    # This sets a low-priority name. It will be
    # overwritten by the high-priority execve name.
    set_fallback_comm(pid, comm_name)

    # --- 3. Dispatch to Line Handlers ---
    # We use anchored regex for safety (won't match args).
    if (line_content ~ /^(execveat|execve)\(/) {
        handle_execve(pid, timestamp, line_content)
    } else if (line_content ~ /^(clone|fork|vfork)\(/) {
        handle_clone(pid, timestamp, line_content)
    } else if (line_content ~ /^(exit_group|\+\+\+ exited)/) {
        handle_exit(pid, timestamp)
    }
}

# ----------------------------------------------------------------------------------

# --- Line Handlers ---

# Sets the command name from <comm> only if one isn't already set
# by the high-priority execve handler.
function set_fallback_comm(pid, comm_name) {
    if (comm_name != "" && pids[pid]["cmd"] == "") {
        pids[pid]["cmd"] = comm_name
    }
}

# Handles clone, fork, and vfork to establish parent-child relationships.
function handle_clone(parent_pid, timestamp, line_content,   m, child_pid) {
    if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)/, m)) {
        child_pid = m[2]
    } else if (match(line_content, /^(clone|fork|vfork)\(.*\)\s+=\s+([0-9]+)<[^>]+>/, m)) {
        child_pid = m[2] # Handle <comm> on RHS
    } else {
        return # Not a successful clone line
    }

    if (child_pid > 0) {
        children[parent_pid][child_pid] = 1
        pids[child_pid]["parent_pid"] = parent_pid
        # Provisionally set start_time for transient (non-execve) processes.
        # This will be overwritten by execve if it occurs.
        pids[child_pid]["start_time"] = timestamp
    }
}

# Handles execve and execveat to set the canonical command name and start time.
function handle_execve(pid, timestamp, line_content,   m_exec, executable_path, args_str, cmd_name) {
    # Match execve OR execveat
    if (match(line_content, /^(execveat|execve)\(.*?("([^"]+)", \[([^\]]+)\])/, m_exec)) {
        pids[pid]["had_execve"] = 1       # Mark this as a "real" process
        pids[pid]["start_time"] = timestamp # This is the *real* start time

        executable_path = m_exec[3]
        args_str = m_exec[4]

        # Call dispatcher to run heuristics and get the command name
        cmd_name = get_command_name(executable_path, args_str)

        pids[pid]["cmd"] = cmd_name # This overwrites any fallback name
    }
}

# Handles exit_group and +++ exited to set the end time.
function handle_exit(pid, timestamp) {
    if (pids[pid]["end_time"] == 0) {
        pids[pid]["end_time"] = timestamp
    }
}

# ----------------------------------------------------------------------------------

# --- Command Name Heuristics ---

# Cleans and splits the execve argument string.
function get_clean_args(args_str,   args, i) {
    # Split args string, allowing for "arg", "arg" or "arg","arg"
    split(args_str, args, /, */)

    # Trim whitespace AND quotes from all arguments
    for (i in args) {
        gsub(/^"|"$/, "", args[i])           # Remove surrounding quotes
        gsub(/^[ \t]+|[ \t]+$/, "", args[i]) # Remove leading/trailing space/tab
    }
}

# Dispatcher for finding the best command name.
function get_command_name(executable_path, args_str,   args, basename_exe) {
    basename_exe = executable_path
    gsub(/.*\//, "", basename_exe)

    # We must get args first, as heuristics depend on them
    get_clean_args(args_str, args)

    if (basename_exe == "bats-exec-test" || basename_exe == "bats") {
        return get_name_bats(basename_exe, args)
    }

    if (basename_exe ~ /^(bash|sh|zsh|dash)$/) {
        return get_name_shell(basename_exe, args)
    }

    return get_name_default(basename_exe)
}

# Heuristic for BATS test runners.
function get_name_bats(basename_exe, args,   i, test_file, test_name) {
    test_file = ""
    test_name = ""
    # This heuristic is tricky.
    # For `bats-exec-test`, we want `test_file;test_name`.
    # For `bats`, it depends. If called with `-T`, the test wants the test file name.
    # If called without `-T` (like in the UNIT test), it wants `bats`.

    is_bats_exec_test = (basename_exe == "bats-exec-test")

    for (i = 2; i <= length(args); i++) {
        if (args[i] ~ /\.bats$/) {
            test_file = args[i]
            if ((i + 1) <= length(args)) {
                test_name = args[i+1]
            }
            break
        }
    }

    if (is_bats_exec_test && test_file != "" && test_name != "" && substr(test_name, 1, 1) != "-") {
        gsub(/.*\//, "", test_file)
        return test_file ";" test_name
    }

    if (basename_exe == "bats") {
        # Check for -T flag
        has_T_flag = 0
        for (i in args) {
            if (args[i] == "-T") {
                has_T_flag = 1
                break
            }
        }
        if (has_T_flag && test_file != "") {
            gsub(/.*\//, "", test_file)
            return test_file
        }
    }

    return basename_exe
}

# Heuristic for shell scripts (e.g., "bash my_script.sh").
function get_name_shell(basename_exe, args,   basename_arg1) {
    if (args[2] != "" && substr(args[2], 1, 1) != "-") {
        basename_arg1 = args[2]
        gsub(/.*\//, "", basename_arg1)
        return basename_arg1
    }
    # Fallback to just "bash" if it's "bash -c ..."
    return basename_exe
}

# Default: just use the basename of the executable.
function get_name_default(basename_exe) {
    return basename_exe
}

# ----------------------------------------------------------------------------------

# --- Stack Building & Filtering ---

# Recursively walks up the parent tree to build the collapsed stack string.
function get_stack(pid,   stack_str, current_pid, parent_pid, cmd_name, default_name, had_execve) {
    stack_str = ""
    current_pid = pid
    while (current_pid in pids) {
        cmd_name = pids[current_pid]["cmd"]
        had_execve = pids[current_pid]["had_execve"]

        # --- Fallback Logic for missing names ---
        if (cmd_name == "") {
            parent_pid = pids[current_pid]["parent_pid"]
            if (parent_pid in pids && pids[parent_pid]["cmd"] != "") {
                cmd_name = pids[parent_pid]["cmd"]
            }
            if (cmd_name == "") {
                cmd_name = "-NO_EXECVE-" current_pid
            }
        }

        # --- Filtering Logic ---
        # If the command is a shell AND it never called execve,
        # it's a transient helper and should be skipped.
        if (cmd_name ~ /^(bash|sh|zsh|dash)$/ && had_execve != 1) {
            # Only skip if it's not the root process
            if (pids[current_pid]["parent_pid"] != "") {
                current_pid = pids[current_pid]["parent_pid"]
                continue # Skip this helper frame, move up.
            }
        }

        # --- Stack Assembly ---
        stack_str = (stack_str == "") ? cmd_name : (cmd_name ";" stack_str)

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
# (This block remains unchanged)
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

    # Pass 3: Aggregate Stacks and Generate Output
    for (pid in pids) {
        if (pids[pid]["self_dur"] > 0) {

            # --- Filter transient shells ---
            # We must apply the same filter logic from get_stack() here.
            cmd_name = pids[pid]["cmd"]
            had_execve = pids[pid]["had_execve"]
            if (cmd_name ~ /^(bash|sh|zsh|dash)$/ && had_execve != 1) {
                if (pids[pid]["parent_pid"] != "") {
                    continue # Skip this transient PID
                }
            }
            # --- End Filter ---

            stack = get_stack(pid)
            weight = int(pids[pid]["self_dur"] * 1000000) # Convert seconds to us
            if (weight > 0) {
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
