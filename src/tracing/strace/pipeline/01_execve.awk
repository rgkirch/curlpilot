#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to the Unit Separator character.
    # This MUST match the OFS from the previous script.
    FS = "\037"
}

{
    # Check if the first field is "execve", as output by the previous script.
    if ($1 == "execve") {
        print $0
        # The fields from the previous script are now:
        # $1: "execve"
        # $2: pid
        # $3: comm
        # $4: timestamp
        # $5: syscall (also "execve", from the original line)
        # $6: args
        # $7: retval ("0")

        pid       = $2
        comm      = $3
        timestamp = $4
        args      = $6

        # Now we parse the arguments string ($6) to find the executable path,
        # which is the first quoted string.
        if (match(args, /^"([^"]+)"/, exec_path)) {
            # exec_path[1] will contain just the captured path
            print "EXECVE_PATH:", "PID=" pid, "COMM=" comm, "PATH=" exec_path[1]
        } else {
            # Fallback if the argument format is unexpected
            print "EXECVE_ARGS:", "PID=" pid, "COMM=" comm, "ARGS=" args
        }
    } else {
        print $0
    }
}
