#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

{
    if ($1 == "interrupted_call") {
        # --- This is the logic for processing interrupted_call lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = $5
        reason       = $7 # e.g., "ERESTARTSYS (To be restarted...)"
        strace_log   = $NF

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Sanitize the reason string to get the core error code (e.g., "ERESTARTSYS").
        error_code = reason
        if (match(reason, /^([A-Z]+)/, reason_match)) {
            error_code = reason_match[1]
        }

        # 3. Create a descriptive name for the event.
        event_name = "interrupted_call: " syscall_name " (" error_code ")"

        print "json", "type", $1, "name", event_name, "time_us", time_us, "pid", pid, "strace", strace_log

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
