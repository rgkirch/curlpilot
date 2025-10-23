#!/usr/bin/gawk -f

BEGIN {
    OFS="\037"
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    syscall_re   = "([^\\(]+)"
    args_re      = "(.*)"

    # --- Composed Regex Patterns ---
    # Matches clone(...) = 2732203<bash>
    clone_re = "^" pid_re comm_re " " timestamp_re " clone\\(" args_re "\\) = " pid_re comm_re "$"

    # Matches clone3(...) = 2744395<sh>
    clone3_re = "^" pid_re comm_re " " timestamp_re " clone3\\(" args_re "\\) = " pid_re comm_re "$"

    # Matches syscalls like execve(...) = 0
    execve_re = "^" pid_re comm_re " " timestamp_re " execve\\(" args_re "\\) = (0)$"

    # Matches ANY syscall that returns ESRCH (e.g., kill(PID, 0))
    esrch_error_re = "^" pid_re comm_re " " timestamp_re " " syscall_re "\\(" args_re "\\) = (-1 ESRCH \\(No such process\\))$"

    # New regex for process termination calls like exit(0) = ?
    exit_re = "^" pid_re comm_re " " timestamp_re " exit\\(" args_re "\\)   = \\?$"

    # New regex for process termination calls like exit_group(1) = ?
    exit_group_re = "^" pid_re comm_re " " timestamp_re " exit_group\\(" args_re "\\) = \\?$"

    # New regex for process exit status lines like +++ exited with 1 +++
    exited_re = "^" pid_re comm_re " " timestamp_re " \\+\\+\\+ exited with ([0-9]+) \\+\\+\\+$"

    # New regex for interrupted system calls like wait4(...) = ? ERESTARTSYS ...
    interrupted_call_re = "^" pid_re comm_re " " timestamp_re " " syscall_re "\\(" args_re "\\) = \\? (ERESTARTSYS.*)$"

    # Matches kill(...) = 0
    kill_success_re = "^" pid_re comm_re " " timestamp_re " kill\\(" args_re "\\) = (0)$"

    # Matches +++ killed by SIGTERM +++
    killed_by_signal_re = "^" pid_re comm_re " " timestamp_re " \\+\\+\\+ killed by ([A-Z]+) \\+\\+\\+$"

    # Matches syscalls like open(...) = -1 ENOENT (No such file or directory)
    no_such_file_re = "^" pid_re comm_re " " timestamp_re " " syscall_re "\\(" args_re "\\) = (-1 ENOENT \\(No such file or directory\\))$"

    # Matches signal notifications like --- SIGCHLD { ... } ---
    signal_re = "^" pid_re comm_re " " timestamp_re " --- ([A-Z]+) (\\{.*\\}) ---$"

    # Matches wait4(...) = 2732203
    wait4_re = "^" pid_re comm_re " " timestamp_re " wait4\\(" args_re "\\) = " pid_re "$"

    # Matches wait4(...) = -1 ECHILD (No child processes)
    wait4_error_re = "^" pid_re comm_re " " timestamp_re " wait4\\(" args_re "\\) = (-1 ECHILD \\(No child processes\\))$"
}

{
    if (match($0, execve_re, fields)) {
        print "execve", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else if (match($0, no_such_file_re, fields)) {
        #print "no_such_file", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if (match($0, clone_re, fields)) {
        print "clone", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]
    } else if (match($0, clone3_re, fields)) {
        # This will now catch clone3(...) lines
        print "clone3", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]
    } else if (match($0, esrch_error_re, fields)) {
        # This will now catch ESRCH from kill, etc.
        #print "esrch_error", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if (match($0, signal_re, fields)) {
        #print "signal", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else if (match($0, interrupted_call_re, fields)) {
        # This new block handles the interrupted call line
        #print "interrupted_call", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if (match($0, kill_success_re, fields)) {
        # This will now catch successful kill(...) = 0 lines
        #print "kill_success", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else if (match($0, killed_by_signal_re, fields)) {
        # This will now catch +++ killed by ... +++ lines
        print "killed_by_signal", fields[1], fields[2], fields[3], fields[4]
    } else if (match($0, exit_group_re, fields)) {
        # This new block handles the process exit line
        #print "exit_group", fields[1], fields[2], fields[3], fields[4]
    } else if (match($0, exit_re, fields)) {
        # This new block handles the process exit(0) = ? line
        #print "exit", fields[1], fields[2], fields[3], fields[4]
    } else if (match($0, exited_re, fields)) {
        # This new block handles the +++ exited with ... +++ line
        print "exited", fields[1], fields[2], fields[3], fields[4]
    } else if (match($0, wait4_re, fields)) {
        #print "wait4", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if (match($0, wait4_error_re, fields)) {
        #print "wait4_error", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else {
        # Keep this to see any other lines that are not matched
        print "unmatched", $0
    }
}
