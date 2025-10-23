#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    if ($1 == "exited") {
        pid       = $2
        timestamp = $4
        exit_code = $5

        end_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Print a JSON object that marks the end of this process's span.
        #    The "key" is the PID, which will be used to join with the start event.
        #    We also include the exit_code for context.
        printf "{\"key\": \"%s\", \"end_us\": %s, \"exit_code\": %s}\n", pid, end_us, exit_code

    } else if ($1 == "exit_group") {
        # Assign the raw fields to named variables for clarity.
        pid       = $2
        timestamp = $4
        exit_code = $5

        end_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Print a JSON object that marks the end of this process's span.
        #    The "key" is the PID, which will be used to join with the start event.
        #    We also include the exit_code for context.
        printf "{\"key\": \"%s\", \"end_us\": %s, \"exit_code\": %s}\n", pid, end_us, exit_code

    } else if ($1 == "exit") {
        # This new block handles lines tagged as "exit" from script 01
        # e.g., 34363<node> 1761175408.226583 exit(0) = ?
        pid       = $2
        timestamp = $4
        exit_code = $5 # This is the "0" from exit(0)

        # 1. Convert timestamp to microseconds. This is an "end time".
        end_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Print a JSON object that marks the end of this process's span.
        printf "{\"key\": \"%s\", \"end_us\": %s, \"exit_code\": %s}\n", pid, end_us, exit_code

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
