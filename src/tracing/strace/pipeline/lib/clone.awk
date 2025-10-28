#!/usr/bin/gawk -f

BEGIN {
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    args_re      = "(.*)"

    # Matches clone(...) = 2732203<bash>
    clone_re = "^" pid_re comm_re " +" timestamp_re " clone\\(" args_re "\\) = " pid_re comm_re "$"

    # Matches clone3(...) = 2744395<sh>
    clone3_re = "^" pid_re comm_re " +" timestamp_re " clone3\\(" args_re "\\) = " pid_re comm_re "$"
}

# --- Matcher Functions ---

function match_clone_re(line, fields) {
    return match(line, clone_re, fields)
}

function match_clone3_re(line, fields) {
    return match(line, clone3_re, fields)
}

# --- Processor Functions ---

function process_clone(f, data, original_line,     # Local vars
                       parent_pid, parent_comm, timestamp, clone_args,
                       child_pid, child_comm, strace_log, start_us, span_name) {

    # Assign fields from the match array
    parent_pid  = f[1]
    parent_comm = f[2]
    timestamp   = f[3]
    clone_args  = f[4]
    child_pid   = f[5]
    child_comm  = f[6]
    strace_log  = original_line

    # 1. Convert timestamp to microseconds
    start_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Create the span name
    span_name = child_comm " <" child_pid "> clone(" clone_args ") from " parent_comm " <" parent_pid ">"
    
    # 3. Populate the data array
    data[1] = "type";       data[2] = "clone"
    data[3] = "name";       data[4] = span_name
    data[5] = "start_us";   data[6] = start_us
    data[7] = "pid";        data[8] = child_pid
    data[9] = "parent_pid"; data[10] = parent_pid
    data[11] = "strace";    data[12] = strace_log
}

function process_clone3(f, data, original_line,     # Local vars
                        parent_pid, parent_comm, timestamp, clone_args,
                        child_pid, child_comm, strace_log, start_us, span_name) {

    # Assign fields from the match array
    parent_pid  = f[1]
    parent_comm = f[2]
    timestamp   = f[3]
    clone_args  = f[4]
    child_pid   = f[5]
    child_comm  = f[6]
    strace_log  = original_line

    # 1. Convert timestamp to microseconds
    start_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Create the span name
    span_name = child_comm " <" child_pid "> clone3(" clone_args ") from " parent_comm " <" parent_pid ">"

    # 3. Populate the data array
    data[1] = "type";       data[2] = "clone3"
    data[3] = "name";       data[4] = span_name
    data[5] = "start_us";   data[6] = start_us
    data[7] = "pid";        data[8] = child_pid
    data[9] = "parent_pid"; data[10] = parent_pid
    data[11] = "strace";    data[12] = strace_log
}
