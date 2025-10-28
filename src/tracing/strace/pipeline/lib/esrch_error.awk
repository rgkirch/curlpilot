#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    syscall_re   = "([^\\(]+)"
    args_re      = "(.*)"

    # Matches: 100<parent> 1.234 kill(...) = -1 ESRCH (No such process)
    esrch_error_re = "^" pid_re comm_re " +" timestamp_re " " syscall_re "\\(" args_re "\\) = (-1 ESRCH \\(No such process\\))$"
}

# --- Matcher Function ---

function match_esrch_error_re(line, fields) {
    return match(line, esrch_error_re, fields)
}

# --- Processor Function ---

function process_esrch_error(f, data, original_line,     # Local vars
                             pid, timestamp, syscall_name, args,
                             strace_log, time_us, target_pid, pid_match, event_name) {

    # Assign fields from the match array
    pid          = f[1]
    timestamp    = f[3]
    syscall_name = f[4]
    args         = f[5]
    strace_log   = original_line

    # 1. Convert timestamp to microseconds
    time_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Try to find the target PID
    target_pid = "unknown_pid"
    if (match(args, /^([0-9]+)/, pid_match)) {
        target_pid = pid_match[1]
    }

    # 3. Create a descriptive name for the event
    event_name = "ESRCH: " syscall_name " on PID " target_pid

    # 4. Populate the data array
    data[1] = "type";       data[2] = "esrch_error"
    data[3] = "name";       data[4] = event_name
    data[5] = "time_us";    data[6] = time_us
    data[7] = "pid";        data[8] = pid
    data[9] = "strace";     data[10] = strace_log
}
