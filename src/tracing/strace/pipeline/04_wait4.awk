#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "wait4".
    if ($1 == "wait4") {
        # --- This is the logic for processing wait4 lines ---

        # Assign the raw fields to named variables for clarity.
        # For a wait4 line, the last field is the PID of the child that was reaped.
        parent_pid           = $2
        timestamp            = $4
        child_pid_waited_for = $6

        # 1. Convert timestamp to microseconds. This is a potential "end time" for the child process.
        end_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Print a JSON object that marks the end of the child's span.
        #    The "key" is the child's PID, which will be used to join with the start event.
        #    The "parent_key" identifies the process that reaped this child.
        printf "{\"key\": \"%s\", \"end_us\": %s, \"parent_key\": \"%s\"}\n", child_pid_waited_for, end_us, parent_pid

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
