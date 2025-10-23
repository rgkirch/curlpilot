#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "signal".
    if ($1 == "signal") {
        # --- This is the logic for processing signal lines ---

        # Assign the raw fields to named variables for clarity.
        parent_pid     = $2
        timestamp      = $4
        signal_name    = $5 # e.g., "SIGCHLD"
        signal_details = $6 # e.g., "{si_signo=SIGCHLD, ...}"

        # We are primarily interested in SIGCHLD as it tells us about child processes.
        if (signal_name == "SIGCHLD") {
            # We need to parse the details string to find out what happened to the child.
            # We are looking for the child's PID (si_pid) and the event code (si_code).

            child_pid = ""
            event_code = ""

            if (match(signal_details, /si_pid=([0-9]+)/, pid_match)) {
                child_pid = pid_match[1]
            }
            if (match(signal_details, /si_code=([A-Z_]+)/, code_match)) {
                event_code = code_match[1]
            }

            # If the code is CLD_EXITED, it means the child process has terminated.
            # This is a high-quality "end time" for that child's span.
            if (child_pid != "" && event_code == "CLD_EXITED") {
                # 1. Convert timestamp to microseconds.
                end_us = sprintf("%.0f", timestamp * 1000000)

                # 2. Print a JSON object that marks the end of the child's span.
                printf "{\"pid\": \"%s\", \"end_us\": %s, \"parent_pid\": \"%s\"}\n", child_pid, end_us, parent_pid
            }
            # (Future enhancement: Other event_codes like CLD_STOPPED could be handled here).
        }
        # (Future enhancement: Other signals like SIGSEGV could be handled here).

    } else {
        # Pass through any other lines (like JSON from previous scripts) unmodified.
        print $0
    }
}
