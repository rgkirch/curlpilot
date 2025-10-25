#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

{
    if ($1 == "kill_success") {
        #23492<bash> 1761175376.777539 kill(23990<bash>, 0) = 0
        #kill_success^_23492^_bash^_1761175376.777539^_23990<bash>, 0^_0
        # --- This is the logic for processing successful kill lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = "kill" # From the regex in script 01
        args         = $5
        strace_log   = $NF

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Try to find the target PID that was checked.
        #    For kill(2744084<bash>, 0), this is the first argument.
        target_pid = "unknown_pid"
        if (match(args, /^([0-9]+)/, pid_match)) {
            target_pid = pid_match[1]
        }

        # 3. Create a descriptive name for the event.
        event_name = "Process Check (kill 0) on PID " target_pid ": Success"

        print "json", "type", "kill_success", "event_name", event_name, "time_us", time_us, "pid", pid, "strace", strace_log

    } else if ($1 == "killed_by_signal") {
        # 2749167<sleep> 1760982700.132394 +++ killed by SIGTERM +++
        # killed_by_signal^_2749167^_sleep^_1760982700.132394^_SIGTERM
        # --- This is the logic for processing killed_by_signal lines ---

        # Assign the raw fields to named variables for clarity.
        pid       = $2
        timestamp = $4
        signal    = $5 # e.g., "SIGTERM"
        strace_log = $NF

        # 1. Convert timestamp to microseconds. This is a definitive "end time".
        end_us = sprintf("%.0f", timestamp * 1000000)

        print "json", "type", "killed_by_signal", "pid", pid, "end_us", end_us, "termination_signal", signal, "strace", strace_log

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
