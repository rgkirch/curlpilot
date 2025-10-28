#!/usr/bin/gawk -f

BEGIN {
    # Define regex components
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"

    # Matches: 100<parent> 1.234 --- SIGCHLD {...} ---
    signal_re = "^" pid_re comm_re " +" timestamp_re " --- ([A-Z]+) (\\{.*\\}) ---$"
}

# --- Matcher Function ---

function match_signal_re(line, fields) {
    return match(line, signal_re, fields)
}

# --- Processor Function ---

function process_signal(f, data, original_line,     # Local vars
                        parent_pid, timestamp, signal_name, signal_details,
                        strace_log, child_pid, event_code, pid_match, code_match, end_us) {

    # Assign fields from the match array
    parent_pid     = f[1]
    timestamp      = f[3]
    signal_name    = f[4] # e.g., "SIGCHLD"
    signal_details = f[5] # e.g., "{si_signo=SIGCHLD, ...}"
    strace_log     = original_line

    # We are primarily interested in SIGCHLD
    if (signal_name == "SIGCHLD") {
        # Parse details to find the child's PID and event code
        child_pid = ""
        event_code = ""

        if (match(signal_details, /si_pid=([0-9]+)/, pid_match)) {
            child_pid = pid_match[1]
        }
        if (match(signal_details, /si_code=([A-Z_]+)/, code_match)) {
            event_code = code_match[1]
        }

        # If the code is CLD_EXITED, create a 'cld_exited' event.
        # This is a high-quality "end time" for that child's span.
        if (child_pid != "" && event_code == "CLD_EXITED") {
            # 1. Convert timestamp to microseconds
            end_us = sprintf("%.0f", timestamp * 1000000)

            # 2. Populate the data array
            data[1] = "type";       data[2] = "cld_exited"
            data[3] = "pid";        data[4] = child_pid
            data[5] = "end_us";     data[6] = end_us
            data[7] = "parent_pid"; data[8] = parent_pid
            data[9] = "strace";     data[10] = strace_log
        }
        # (Future enhancement: Other event_codes like CLD_STOPPED could be handled here)
    }
    # (Future enhancement: Other signals like SIGSEGV could be handled here)

    # If it's not a SIGCHLD CLD_EXITED event, the 'data' array remains
    # empty, and the main script will correctly print nothing.
}
