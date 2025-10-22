#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "interrupted_call".
    if ($1 == "interrupted_call") {
        # --- This is the logic for processing interrupted_call lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = $5
        reason       = $7 # e.g., "ERESTARTSYS (To be restarted...)"

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Sanitize the reason string to get the core error code (e.g., "ERESTARTSYS").
        error_code = reason
        if (match(reason, /^([A-Z]+)/, reason_match)) {
            error_code = reason_match[1]
        }

        # 3. Create a descriptive name for the event.
        event_name = "interrupted_call: " syscall_name " (" error_code ")"

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
