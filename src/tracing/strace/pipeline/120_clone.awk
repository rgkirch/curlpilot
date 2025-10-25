#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

{
    # We only want to process lines that the first script tagged as "clone".
    if ($1 == "clone") {
        # --- This is the logic for processing clone lines ---

        # Assign the raw fields to named variables for clarity.
        parent_pid  = $2
        parent_comm = $3
        timestamp   = $4
        clone_args  = $5  # <-- Capture the clone() arguments
        child_pid   = $6
        child_comm  = $7
        strace_log  = $9

        # 1. Convert timestamp to microseconds. This is the "start time" for the new child process.
        start_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Create a temporary span name for the new child. This name can be
        #    updated later when this child process calls execve.
        #    This is the new, more descriptive name:
        span_name = child_comm " <" child_pid "> clone(" clone_args ") from " parent_comm " <" parent_pid ">"

        print "json", "type", $1, "name", span_name, "start_us", start_us, "pid", child_pid, "parent_pid", parent_pid, "strace", strace_log

    } else if ($1 == "clone3") {

        parent_pid  = $2
        parent_comm = $3
        timestamp   = $4
        clone_args  = $5  # <-- Capture the clone3() arguments
        child_pid   = $6
        child_comm  = $7
        strace_log  = $9

        # 1. Convert timestamp to microseconds. This is the "start time" for the new child process.
        start_us = sprintf("%.0f", timestamp * 1000000)

        # 2. Create a temporary span name for the new child.
        #    This is the new, more descriptive name:
        span_name = child_comm " <" child_pid "> clone3(" clone_args ") from " parent_comm " <" parent_pid ">"

        # 3. Escape any quotes in the span name to ensure valid JSON.
        print "json", "type", $1, "name", span_name, "start_us", start_us, "pid", child_pid, "parent_pid", parent_pid, "strace", strace_log

    } else {
        # Pass through any other lines (like the JSON from the execve script) unmodified.
        print $0
    }
}
