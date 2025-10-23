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
        #    The "pid" is the child's PID, which will be used to join with the start event.
        #    The "parent_pid" identifies the process that reaped this child.
        printf "{\"type\": \"wait4\", \"pid\": \"%s\", \"end_us\": %s, \"parent_pid\": \"%s\"}\n", child_pid_waited_for, end_us, parent_pid

    } else if ($1 == "wait4_error") {
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
