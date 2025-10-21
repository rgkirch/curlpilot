#!/usr/bin/awk -f

BEGIN {
    OFS="\037"
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    syscall_re   = "([^\\(]+)"
    args_re      = "(.*)"
    successfull_call_re = "^" pid_re comm_re " " timestamp_re " " syscall_re "\\(" args_re "\\) = (0)$"
    #print "successful call re: " successfull_call_re
    failed_call_re = "^" pid_re comm_re " " timestamp_re " " syscall_re "\\(" args_re "\\) = (-1 ENOENT \\(No such file or directory\\))$"
    #print "failed call re: " failed_call_re
    clone_re = "^" pid_re comm_re " " timestamp_re " clone\\(" args_re "\\) = " pid_re comm_re "$"
    wait_re = "^" pid_re comm_re " " timestamp_re " wait4\\(" args_re "\\) = " pid_re "$"
    wait_error_re = "^" pid_re comm_re " " timestamp_re " wait4\\(" args_re "\\) = (-1 ECHILD \\(No child processes\\))$"

}

{
    if(match($0, successfull_call_re, fields)) {
        #print "successfull call", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if(match($0, failed_call_re, fields)) {
        #print "failed call", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if(match($0, clone_re, fields)) {
        #print "cloning: ", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
    } else if(match($0, wait_re, fields)) {
        #print "wait: ", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else if(match($0, wait_error_re, fields)) {
        #print "wait error: ", fields[1], fields[2], fields[3], fields[4], fields[5]
    } else {
        print "failed to match: ", $0
    }

}
