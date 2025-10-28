#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    args_re      = "(.*)"

    # Matches wait4(...) = 2732203
    wait4_re = "^" pid_re comm_re " +" timestamp_re " wait4\\(" args_re "\\) = " pid_re "$"

    # Matches wait4(...) = -1 ECHILD (No child processes)
    wait4_error_re = "^" pid_re comm_re " +" timestamp_re " wait4\\(" args_re "\\) = (-1 ECHILD \\(No child processes\\))$"
}

# --- Matcher Functions ---

function match_wait4_re(line, fields) {
    return match(line, wait4_re, fields)
}

function match_wait4_error_re(line, fields) {
    return match(line, wait4_error_re, fields)
}

# --- Processor Functions ---

function process_wait4(f, data, original_line,     # Local vars
                       parent_pid, timestamp, child_pid_waited_for,
                       strace_log, end_us) {

    # Assign fields from the match array
    parent_pid           = f[1]
    timestamp            = f[3]
    child_pid_waited_for = f[5]
    strace_log           = original_line

    # 1. Convert timestamp to microseconds
    end_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Populate the data array
    data[1] = "type";       data[2] = "wait4"
    data[3] = "pid";        data[4] = child_pid_waited_for
    data[5] = "end_us";     data[6] = end_us
    data[7] = "parent_pid"; data[8] = parent_pid
    data[9] = "strace";     data[10] = strace_log
}

function process_wait4_error(f, data, original_line,     # Local vars
                             parent_pid, timestamp, error_msg, strace_log,
                             time_us, event_name, err_match) {

    # Assign fields from the match array
    parent_pid = f[1]
    timestamp  = f[3]
    error_msg  = f[5] # e.g., "-1 ECHILD (No child processes)"
    strace_log = original_line

    # 1. Convert timestamp to microseconds
    time_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Sanitize the error message
    event_name = "wait4_error: unknown"
    if (match(error_msg, /-1 ([A-Z]+)/, err_match)) {
        event_name = "wait4_error: " err_match[1]
    }

    # 3. Populate the data array
    data[1] = "type";       data[2] = "wait4_error"
    data[3] = "event_name"; data[4] = event_name
    data[5] = "time_us";    data[6] = time_us
    data[7] = "pid";        data[8] = parent_pid
    data[9] = "strace";     data[10] = strace_log
}
