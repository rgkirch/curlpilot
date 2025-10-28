#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    args_re      = "(.*)"

    # Matches: 23492<bash> 1761175376.777539 kill(23990<bash>, 0) = 0
    kill_success_re = "^" pid_re comm_re " +" timestamp_re " kill\\(" args_re "\\) = (0)$"

    # Matches: 2749167<sleep> 1760982700.132394 +++ killed by SIGTERM +++
    killed_by_signal_re = "^" pid_re comm_re " +" timestamp_re " \\+\\+\\+ killed by ([A-Z]+) \\+\\+\\+$"
}

# --- Matcher Functions ---

function match_kill_success_re(line, fields) {
    return match(line, kill_success_re, fields)
}

function match_killed_by_signal_re(line, fields) {
    return match(line, killed_by_signal_re, fields)
}

# --- Processor Functions ---

function process_kill_success(f, data, original_line,     # Local vars
                            pid, timestamp, args, strace_log,
                            time_us, target_pid, pid_match, event_name) {

    # Assign fields from the match array
    pid         = f[1]
    timestamp   = f[3]
    args        = f[4]
    strace_log  = original_line

    # 1. Convert timestamp to microseconds
    time_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Try to find the target PID
    target_pid = "unknown_pid"
    if (match(args, /^([0-9]+)/, pid_match)) {
        target_pid = pid_match[1]
    }

    # 3. Create a descriptive name for the event
    event_name = "Process Check (kill 0) on PID " target_pid ": Success"

    # 4. Populate the data array
    data[1] = "type";       data[2] = "kill_success"
    data[3] = "name";       data[4] = event_name
    data[5] = "time_us";    data[6] = time_us
    data[7] = "pid";        data[8] = pid
    data[9] = "strace";     data[10] = strace_log
}

function process_killed_by_signal(f, data, original_line,     # Local vars
                                pid, timestamp, signal, strace_log, end_us) {

    # Assign fields from the match array
    pid         = f[1]
    timestamp   = f[3]
    signal      = f[4] # e.g., "SIGTERM"
    strace_log  = original_line

    # 1. Convert timestamp to microseconds
    end_us = sprintf("%.0f", timestamp * 1000000)

    # 2. Populate the data array
    data[1] = "type";       data[2] = "killed_by_signal"
    data[3] = "pid";        data[4] = pid
    data[5] = "end_us";     data[6] = end_us
    data[7] = "termination_signal"; data[8] = signal
    data[9] = "strace";     data[10] = strace_log
}
