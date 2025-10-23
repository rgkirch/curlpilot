#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "kill_success".
    if ($1 == "kill_success") {
        #23492<bash> 1761175376.777539 kill(23990<bash>, 0) = 0
        #kill_success^_23492^_bash^_1761175376.777539^_23990<bash>, 0^_0
        # --- This is the logic for processing successful kill lines ---

        # Assign the raw fields to named variables for clarity.
        pid          = $2
        timestamp    = $4
        syscall_name = "kill" # From the regex in script 01
        args         = $5
        # $6 is the return value "0"

        # 1. Convert timestamp to microseconds.
        time_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Try to find the target PID that was checked.
        #    For kill(2744084<bash>, 0), this is the first argument.
        target_pid = "unknown_pid"
        if (match(args, /^([0-9]+)/, pid_match)) {
            target_pid = pid_match[1]
        }

        # 3. Create a descriptive name for the event.
        event_name = "Process Check (kill 0) on PID " target_pid ": Success"

        # 4. Escape any quotes in the event name to ensure valid JSON.
        gsub(/"/, "\\\"", event_name)

        # 5. Print a JSON object that represents a single event in the process's timeline.
        #    The "pid" is the PID, associating this event with the correct span.
        printf "{\"type\": \"kill_success\", \"event_name\": \"%s\", \"time_us\": %s, \"pid\": \"%s\"}\n", event_name, time_us, pid

    } else if ($1 == "killed_by_signal") {
        # 2749167<sleep> 1760982700.132394 +++ killed by SIGTERM +++
        # killed_by_signal^_2749167^_sleep^_1760982700.132394^_SIGTERM
        # --- This is the logic for processing killed_by_signal lines ---

        # Assign the raw fields to named variables for clarity.
        pid       = $2
        timestamp = $4
        signal    = $5 # e.g., "SIGTERM"

        # 1. Convert timestamp to microseconds. This is a definitive "end time".
        end_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Store the signal as the termination reason.
        gsub(/"/, "\\\"", signal) # Escape for JSON

        # 3. Print a JSON object that marks the end of this process's span.
        #    The "pid" is the PID, which will be used to join with the start event.
        printf "{\"type\": \"killed_by_signal\", \"pid\": \"%s\", \"end_us\": %s, \"termination_signal\": \"%s\"}\n", pid, end_us, signal

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
