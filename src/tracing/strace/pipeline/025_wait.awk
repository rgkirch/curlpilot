#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

{
    if ($1 == "wait4") {
        # --- This is the logic for processing wait4 lines ---

        # Assign the raw fields to named variables for clarity.
        # For a wait4 line, the last field is the PID of the child that was reaped.
        parent_pid           = $2
        timestamp            = $4
        child_pid_waited_for = $6
        strace_log           = $NF

        # 1. Convert timestamp to microseconds. This is a potential "end time" for the child process.
        end_us = sprintf("%.0f", timestamp * 1000000)

        print "json", "type", "wait4", "pid", child_pid_waited_for, "end_us", end_us, "parent_pid", parent_pid, "strace", strace_log

    } else if ($1 == "wait4_error") {
        # --- This is the logic for processing wait4_error lines ---

        # Assign the raw fields to named variables for clarity.
        parent_pid = $2
        timestamp  = $4
        error_msg  = $6 # e.g., "-1 ECHILD (No child processes)"
        strace_log = $NF

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Sanitize the error message for use as an event name.
        #    We'll extract the core error, like "ECHILD".
        event_name = "wait4_error: unknown"
        if (match(error_msg, /-1 ([A-Z]+)/, err_match)) {
            event_name = "wait4_error: " err_match[1]
        }

        print "json", "type", "wait4_error", "event_name", event_name, "time_us", time_us, "pid", parent_pid, "strace", strace_log

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
