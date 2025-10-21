# This AWK script processes strace logs to extract process facts
# and print them as JSON Lines, one object per PID.
# This output is intended for a downstream tool (e.g., Clojure)
# to build the final process hierarchy/tree.

# --- Global Data Structures ---
# pids[pid]["parent_pid"]     = The parent PID of this process
# pids[pid]["cmd"]            = The command name (from execve OR comm)
# pids[pid]["start_time"]     = The timestamp (from clone OR execve)
# pids[pid]["end_time"]       = The timestamp of the exit_group call
# pids[pid]["had_execve"]     = Flag (1) if this process called execve.
# pids[pid]["total_dur"]      = Calculated total duration (end - start)
# children[pid][child_pid]  = An array holding the PIDs of children

# --- Main Block (Dispatcher) ---
{
    # --- 1. Universal Line Parsing ---
    if ($1 !~ /<.*>/) {
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
    set_fallback_comm(pid, comm_name)

    # --- 3. Dispatch to Line Handlers ---
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

function set_fallback_comm(pid, comm_name) {
    if (comm_name != "" && pids[pid]["cmd"] == "") {
        pids[pid]["cmd"] = comm_name
    }
}

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
        pids[child_pid]["start_time"] = timestamp
    }
}

function handle_execve(pid, timestamp, line_content,   m_exec, executable_path, args_str, cmd_name) {
    if (match(line_content, /^(execveat|execve)\(.*?("([^"]+)", \[([^\]]+)\])/, m_exec)) {
        if (line_content !~ /\)\s+=\s+0\s*$/) {
            return # This was a failed execve (e.g., = -1 ENOENT)
        }
        pids[pid]["had_execve"] = 1
        pids[pid]["start_time"] = timestamp # This is the *real* start time

        executable_path = m_exec[3]
        args_str = m_exec[4]

        cmd_name = get_command_name(executable_path, args_str)
        pids[pid]["cmd"] = cmd_name
    }
}

function handle_exit(pid, timestamp) {
    if (pids[pid]["end_time"] == 0) {
        pids[pid]["end_time"] = timestamp
    }
}

# ----------------------------------------------------------------------------------

# --- Command Name Heuristics ---
# (All functions retained exactly as you wrote them)

function get_clean_args(args_str,   args, i) {
    split(args_str, args, /, */)
    for (i in args) {
        gsub(/^"|"$/, "", args[i])
        gsub(/^[ \t]+|[ \t]+$/, "", args[i])
    }
}

function get_command_name(executable_path, args_str,   args, basename_exe) {
    basename_exe = executable_path
    gsub(/.*\//, "", basename_exe)

    get_clean_args(args_str, args)

    if (basename_exe == "bats-exec-test" || basename_exe == "bats") {
        return get_name_bats(basename_exe, args)
    }

    if (basename_exe ~ /^(bash|sh|zsh|dash)$/) {
        return get_name_shell(basename_exe, args)
    }

    return get_name_default(basename_exe)
}

function get_name_bats(basename_exe, args,   i, test_file, test_name, has_T_flag, is_bats_exec_test) {
    test_file = ""
    test_name = ""
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

function get_name_shell(basename_exe, args,   basename_arg1) {
    if (args[2] != "" && substr(args[2], 1, 1) != "-") {
        basename_arg1 = args[2]
        gsub(/.*\//, "", basename_arg1)
        return basename_arg1
    }
    return basename_exe
}

function get_name_default(basename_exe) {
    return basename_exe
}

# ----------------------------------------------------------------------------------
# --- END Block (REPLACED) ---
#
# This block no longer calculates self-time or aggregates stacks.
# It just calculates total duration and prints all process facts
# as JSON-Lines, ready for Clojure to consume.
# ----------------------------------------------------------------------------------

END {
    # Pass 1: Calculate Total Durations
    for (pid in pids) {
        if (pids[pid]["start_time"] > 0 && pids[pid]["end_time"] > 0) {
            pids[pid]["total_dur"] = pids[pid]["end_time"] - pids[pid]["start_time"]
        } else {
            pids[pid]["total_dur"] = 0
        }
    }

    # Pass 2: Print all process data as JSON Lines
    for (pid in pids) {
        # Escape quotes and backslashes in the command name for valid JSON
        cmd = pids[pid]["cmd"]
        gsub(/\\/, "\\\\", cmd)
        gsub(/"/, "\\\"", cmd)

        # Use JSON null for missing parents
        parent_pid = pids[pid]["parent_pid"]
        if (parent_pid == "") {
            parent_pid = "null"
        }

        # Print all facts for this process on a single line
        printf "{\"pid\": %s, \"ppid\": %s, \"cmd\": \"%s\", \"start\": %f, \"end\": %f, \"total_dur\": %f, \"had_execve\": %d}\n",
            pid,
            parent_pid,
            cmd,
            pids[pid]["start_time"] + 0,  # Ensure numeric output even if 0
            pids[pid]["end_time"] + 0,
            pids[pid]["total_dur"] + 0,
            pids[pid]["had_execve"] + 0
    }
}

#awk -f parse.awk /tmp/tmp.HqEnjWa9Y6/strace-logs/trace.*
