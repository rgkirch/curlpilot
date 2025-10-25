#!/usr/bin/gawk -f

BEGIN {
    OFS = FS = "\037"
}

{
    if ($1 == "esrch_error") {
        # --- This is the logic for processing generic ESRCH lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = $5
        args         = $6
        strace_log   = $NF

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Try to find the target PID that was checked.
        #    For kill(2744084, 0), this is the first argument.
        target_pid = "unknown_pid"
        if (match(args, /^([0-9]+)/, pid_match)) {
            target_pid = pid_match[1]
        }

        # 3. Create a descriptive name for the event.
        event_name = "ESRCH: " syscall_name " on PID " target_pid

        print "json", "type", $1, "name", event_name, "time_us", time_us, "pid", pid, "strace", strace_log

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
