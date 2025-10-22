#!/usr/bin/gawk -f

BEGIN {
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "esrch_error".
    if ($1 == "esrch_error") {
        # --- This is the logic for processing generic ESRCH lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = $5
        args         = $6
        # $7 is the error message string

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

        # 4. Escape any quotes in the event name to ensure valid JSON.
        gsub(/"/, "\\\"", event_name)

        # 5. Print a JSON object that represents a single event in the process's timeline.
        #    The "key" is the PID, associating this event with the correct span.
        printf "{\"event_name\": \"%s\", \"time_us\": %s, \"key\": \"%s\"}\n", event_name, time_us, pid

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
