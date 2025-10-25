#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

{
    if ($1 == "exited") {
        pid       = $2
        timestamp = $4
        exit_code = $5
        strace_log = $NF
        end_us = sprintf("%.0f", timestamp * 1000000)

        print "json", "type", "exited", "pid", pid, "end_us", end_us, "exit_code", exit_code, "strace", strace_log

    } else if ($1 == "exit_group") {
        # Assign the raw fields to named variables for clarity.
        pid       = $2
        timestamp = $4
        exit_code = $5
        strace_log = $NF

        end_us = sprintf("%.0f", timestamp * 1000000)

        print "json", "type", "exit_group", "pid", pid, "end_us", end_us, "exit_code", exit_code, "strace", strace_log

    } else if ($1 == "exit") {
        # This new block handles lines tagged as "exit" from script 01
        # e.g., 34363<node> 1761175408.226583 exit(0) = ?
        pid       = $2
        timestamp = $4
        exit_code = $5 # This is the "0" from exit(0)
        strace_log = $NF

        # 1. Convert timestamp to microseconds. This is an "end time".
        end_us = sprintf("%.0f", timestamp * 1000000)

        print "json", "type", "exit", "pid", pid, "end_us", end_us, "exit_code", exit_code, "strace", strace_log

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
