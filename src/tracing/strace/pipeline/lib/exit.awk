#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    args_re      = "(.*)"

    # +++ exited with 1 +++
    exited_re = "^" pid_re comm_re " +" timestamp_re " \\+\\+\\+ exited with ([0-9]+) \\+\\+\\+$"

    # exit_group(1) = ?
    exit_group_re = "^" pid_re comm_re " +" timestamp_re " exit_group\\(" args_re "\\) += \\?$"

    # exit(0) = ?
    exit_re = "^" pid_re comm_re " +" timestamp_re " exit\\(" args_re "\\) += \\?$"
}

# --- Matcher Functions ---

function match_exited_re(line, fields) {
    return match(line, exited_re, fields)
}

function match_exit_group_re(line, fields) {
    return match(line, exit_group_re, fields)
}

function match_exit_re(line, fields) {
    return match(line, exit_re, fields)
}

# --- Processor Functions ---

function process_exited(f, data, original_line,     # Local vars
                        pid, timestamp, exit_code, strace_log, end_us) {

    # Assign fields from the match array
    pid         = f[1]
    timestamp   = f[3]
    exit_code   = f[4]
    strace_log  = original_line

    # 1. Convert timestamp to microseconds
    end_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Populate the data array
    data[1] = "type";       data[2] = "exited"
    data[3] = "pid";        data[4] = pid
    data[5] = "end_us";     data[6] = end_us
    data[7] = "exit_code";  data[8] = exit_code
    data[9] = "strace";     data[10] = strace_log
}

function process_exit_group(f, data, original_line,     # Local vars
                            pid, timestamp, args, exit_code, strace_log, end_us) {

    # Assign fields from the match array
    pid         = f[1]
    timestamp   = f[3]
    args        = f[4] # e.g., "1" from exit_group(1)
    strace_log  = original_line

    # 1. Extract exit code from args
    #    We default to 0 if the regex fails (e.g., empty "exit_group()")
    exit_code = "0"
    if (match(args, /^[0-9]+/, m)) {
        exit_code = m[0]
    }

    # 2. Convert timestamp to microseconds
    end_us = sprintf("%.0f", timestamp * 1000000)

    # 3. Populate the data array
    data[1] = "type";       data[2] = "exit_group"
    data[3] = "pid";        data[4] = pid
    data[5] = "end_us";     data[6] = end_us
    data[7] = "exit_code";  data[8] = exit_code
    data[9] = "strace";     data[10] = strace_log
}

function process_exit(f, data, original_line,     # Local vars
                      pid, timestamp, args, exit_code, strace_log, end_us) {

    # Assign fields from the match array
    pid         = f[1]
    timestamp   = f[3]
    args        = f[4] # e.g., "0" from exit(0)
    strace_log  = original_line

    # 1. Extract exit code from args
    exit_code = "0"
    if (match(args, /^[0-9]+/, m)) {
        exit_code = m[0]
    }

    # 2. Convert timestamp to microseconds
    end_us = sprintf("%.0f", timestamp * 1000000)

    # 3. Populate the data array
    data[1] = "type";       data[2] = "exit"
    data[3] = "pid";        data[4] = pid
    data[5] = "end_us";     data[6] = end_us
    data[7] = "exit_code";  data[8] = exit_code
    data[9] = "strace";     data[10] = strace_log
}
