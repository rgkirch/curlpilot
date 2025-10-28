#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    syscall_re   = "([^\\(]+)"
    args_re      = "(.*)"

    # Matches: 100<parent> 1.234 wait4(...) = ? ERESTARTSYS ...
    interrupted_call_re = "^" pid_re comm_re " +" timestamp_re " " syscall_re "\\(" args_re "\\) = \\? (ERESTARTSYS.*)$"
}

# --- Matcher Function ---

function match_interrupted_call_re(line, fields) {
    return match(line, interrupted_call_re, fields)
}

# --- Processor Function ---

function process_interrupted_call(f, data, original_line,     # Local vars
                                pid, timestamp, syscall_name, reason,
                                strace_log, time_us, error_code, reason_match, event_name) {

    # Assign fields from the match array
    pid          = f[1]
    timestamp    = f[3]
    syscall_name = f[4]
    reason       = f[6] # e.g., "ERESTARTSYS (To be restarted...)"
    strace_log   = original_line

    # 1. Convert timestamp to microseconds
    time_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Sanitize the reason string
    error_code = reason
    if (match(reason, /^([A-Z]+)/, reason_match)) {
        error_code = reason_match[1]
    }

    # 3. Create a descriptive name for the event
    event_name = "interrupted_call: " syscall_name " (" error_code ")"

    # 4. Populate the data array
    data[1] = "type";       data[2] = "interrupted_call"
    data[3] = "name";       data[4] = event_name
    data[5] = "time_us";    data[6] = time_us
    data[7] = "pid";        data[8] = pid
    data[9] = "strace";     data[10] = strace_log
}
