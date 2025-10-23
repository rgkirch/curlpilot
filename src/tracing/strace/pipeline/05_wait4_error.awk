#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "wait4_error".
    if ($1 == "wait4_error") {
        # --- This is the logic for processing wait4_error lines ---

        # Assign the raw fields to named variables for clarity.
        parent_pid = $2
        timestamp  = $4
        error_msg  = $6 # e.g., "-1 ECHILD (No child processes)"

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Sanitize the error message for use as an event name.
        #    We'll extract the core error, like "ECHILD".
        event_name = "wait4_error: unknown"
        if (match(error_msg, /-1 ([A-Z]+)/, err_match)) {
            event_name = "wait4_error: " err_match[1]
        }

        # 3. Escape any quotes in the event name to ensure valid JSON.
        gsub(/"/, "\\\"", event_name)

        # 4. Print a JSON object that represents a single event in the parent's timeline.
        #    The "pid" is the parent's PID, associating this event with the correct span.
        printf "{\"event_name\": \"%s\", \"time_us\": %s, \"pid\": \"%s\"}\n", event_name, time_us, parent_pid

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
