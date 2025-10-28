#!/usr/bin/gawk -f

@include "clone.awk"
@include "esrch_error.awk"
@include "execve.awk"
@include "exit.awk"
@include "json.awk"
@include "wait.awk"
@include "interrupted_call.awk"
@include "kill.awk"
@include "signal.awk"

BEGIN {
    OFS="\037"
    pid_re       = "([0-9]+)"
    comm_re      = "<([^>]+)>"
    timestamp_re = "([0-9]+\\.[0-9]+)"
    syscall_re   = "([^\\(]+)"
    args_re      = "(.*)"

    # --- Composed Regex Patterns ---

    # Matches syscalls like open(...) = -1 ENOENT (No such file or directory)
    no_such_file_re = "^" pid_re comm_re " +" timestamp_re " " syscall_re "\\(" args_re "\\) = (-1 ENOENT \\(No such file or directory\\))$"

}

{
    if (match_execve_re($0, fields)) {
        delete json_data
        process_execve(fields, json_data, $0)
        if (length(json_data) > 0) {
            print_json(json_data)
        }
    } else if (match($0, no_such_file_re, fields)) {
        #print "no_such_file", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], $0
    } else if (match_clone_re($0, fields)) {
        delete json_data
        process_clone(fields, json_data, $0)
        if (length(json_data) > 0) {
            print_json(json_data)
        }
    } else if (match($0, esrch_error_re, fields)) {
        # This will now catch ESRCH from kill, etc.
        #print "esrch_error", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], $0
    } else if (match_signal_re($0, fields)) {
        delete json_data
        process_signal(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match($0, interrupted_call_re, fields)) {
        # This new block handles the interrupted call line
        #print "interrupted_call", fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], $0
    } else if (match_kill_success_re($0, fields)) {
        delete json_data
        process_kill_success(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match_killed_by_signal_re($0, fields)) {
        delete json_data
        process_killed_by_signal(fields, json_data, $0)
        if (length(json_data) > 0) {
            print_json(json_data)
        }
    } else if (match_exited_re($0, fields)) {
        delete json_data
        process_exited(fields, json_data, $0)
        if (length(json_data) > 0) {
            print_json(json_data)
        }
    } else if (match_exit_group_re($0, fields)) {
        delete json_data
        process_exit_group(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match_exit_re($0, fields)) {
        delete json_data
        process_exit(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match_wait4_re($0, fields)) {
        delete json_data
        process_wait4(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match_wait4_error_re($0, fields)) {
        delete json_data
        process_wait4_error(fields, json_data, $0)
        if (length(json_data) > 0) {
            #print_json(json_data)
        }
    } else if (match($0, /[ \t]*/)) {
    } else {
        # Keep this to see any other lines that are not matched
        print "unmatched", $0
    }
}
