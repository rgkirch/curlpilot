#!/usr/bin/awk -f

# This regex will be used to parse lines that are completed syscalls
BEGIN {
    # Regex to capture the 6 fields
    # Note: We don't need to double-escape backslashes for \. \( \)
    # when using the /.../ literal regex notation.
    regex = /^([0-9]+)<([^>]+)> ([0-9]+\.[0-9]+) ([a-zA-Z0-9_]+)\((.*)\) = (.*)$/
}

# Process each line of the input
{
    # Check if the current line ($0) matches the regex
    if (match($0, regex, fields)) {
        # If it matches, assign captures to named variables for clarity
        pid       = fields[1]
        comm      = fields[2]
        timestamp = fields[3]
        syscall   = fields[4]
        args      = fields[5]
        retval    = fields[6]

        # Print the parsed fields (example output)
        print "--- Matched Line ---"
        print "PID:       " pid
        print "Command:   " comm
        print "Timestamp: " timestamp
        print "Syscall:   " syscall
        print "Args:      " args
        print "Return:    " retval
        print ""
    } else {
        # Optional: Print lines that didn't match (e.g., unfinished syscalls)
        # print "--- Skipped Line ---"
        # print $0
        # print ""
    }
}
