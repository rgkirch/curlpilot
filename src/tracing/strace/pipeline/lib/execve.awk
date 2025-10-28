
BEGIN {
    # Define regex components here
    pid_re  = "([0-9]+)"
    comm_re = "<([^>]+)>"
    ts_re   = "([0-9]+\\.[0-9]+)"
    args_re = "(.*)"

    # Matches syscalls like execve(...) = 0
    execve_re = "^" pid_re comm_re " +" ts_re " execve\\(" args_re "\\) = (0)$"
}

# This helper function parses exactly one quoted argument from the start
# of a string. It returns the argument and the remainder of the string
# via the 'result' array (which is passed by reference).
#
# @param arg_string The string to parse (e.g., "arg1", "arg2"]...)
# @param result      An array to store results:
#                   result[1] = the parsed argument (if found)
#                   result[2] = the remainder of the string
# @return             1 if an argument was successfully parsed,
#                   0 if the end bracket or an error was found.
function _parse_single_arg(arg_string, result,    # Local vars
                            match_arr, remainder) {
    # Clear previous results
    delete result

    # 1. Trim whitespace before the next token.
    sub(/^[ \t]+/, "", arg_string)

    # 2. Check if the next token is the closing bracket.
    if (substr(arg_string, 1, 1) == "]") {
        result[1] = ""
        result[2] = substr(arg_string, 2) # Remainder is after ']'
        return 0 # Status code for "stop"
    }

    # 3. If not a ']', try to match *only* the first quoted string,
    #    anchored to the start of the string.
    else if (match(arg_string, /^"([^"\\]*(?:\\.[^"\\]*)*)",? */, match_arr)) {

        # match_arr[1] is the content (e.g., arg1)
        result[1] = match_arr[1]

        # gawk sets RLENGTH to the length of the *full match* (e.g., "arg1",)
        # We use substr() to get everything *after* that match.
        remainder = substr(arg_string, RSTART + RLENGTH)

        # Now we manually clean up the remainder string
        # to remove the comma and spaces that the old regex
        # was supposed to handle.
        sub(/^[ \t]*,?[ \t]*/, "", remainder)

        result[2] = remainder
        return 1 # Status code for "arg found"
    }

    # 4. No quoted string found, and not a ']'
    else {
        result[1] = ""
        result[2] = arg_string
        return 0 # Status code for "stop"
    }
}

# This custom function iteratively parses a string of quoted arguments
# from an execve array like ["arg1", "arg2"].
# It populates a global array named `_parsed_args_global`.
#
# @param arg_string The raw string to parse, STARTING from the array.
#                   e.g., ["arg1", "arg2, with comma"], 0xABC ...
# @return             The remainder of the string *after* the closing bracket.
function parse_args(arg_string,      parse_result, single_arg) {
    # Clear the global array of any old data before populating it.
    delete _parsed_args_global

    # 1. Trim leading whitespace and find the opening bracket.
    sub(/^[ \t]+/, "", arg_string)
    if (substr(arg_string, 1, 1) != "[") {
        # Not an array, nothing to parse.
        return arg_string
    }

    # 2. Remove the opening bracket.
    arg_string = substr(arg_string, 2)

    # 3. Loop as long as _parse_single_arg returns 1 (arg found).
    while (_parse_single_arg(arg_string, parse_result)) {
        single_arg = parse_result[1] # The parsed arg
        arg_string = parse_result[2] # The new remainder
        _parsed_args_global[length(_parsed_args_global) + 1] = single_arg
    }

    # Loop stopped, so _parse_single_arg returned 0.
    # The final remainder is in parse_result[2].
    arg_string = parse_result[2]

    # Return the rest of the string *after* the closing bracket.
    return arg_string
}

# This function constructs the human-readable span name from the
# parsed arguments stored in the global `_parsed_args_global` array.
#
# It performs two transformations:
# 1. Takes the basename of any argument that looks like a path.
# 2. Replaces "--no-" with "--na-" in arguments.
#
# @param program_name The basename of the executable (e.g., "bats")
# @return             A formatted string of all arguments.
function name_span(program_name,     # Local vars
                    i, arg, span_name) {

    span_name = program_name

    # Loop through only the arguments, starting from index 2.
    # _parsed_args_global[1] is the program name itself, which is
    # already included in `span_name` (passed as `program_name`).
    for (i = 2; i in _parsed_args_global; i++) {
        arg = _parsed_args_global[i]

        # 1. Get basename by removing everything up to the last '/'
        sub(/.*\//, "", arg)

        # 2. Perform the required substitution for the test.
        # sub(/--no-/, "--na-", arg) # This was based on a typo in the test case

        # Append the processed argument
        span_name = span_name " " arg
    }

    # Remove the first " "
    # sub(/^[^ ]+ /, "", span_name) # <-- This was the bug

    return span_name
}

function match_execve_re(line, fields) {
    return match(line, execve_re, fields)
}

# Processes an execve event, populating the `data` array with key-value pairs for the JSON output.
# @param f The `fields` array captured by the `match()` function.
# @param data The output array to populate (passed by reference).
# @param original_line The full, original strace log line.
function process_execve(f, data, original_line,    # Local vars
                        pid, timestamp, args_string, strace_log, debug_text,
                        program_name, rest_of_args, span_name, start_us) {
    pid = f[1]
    timestamp = f[3]
    args_string = f[4]
    strace_log = original_line

    if (match(args_string, /^"[^"]*\/([^\/"]+)", (.*)/, path_match)) {
        program_name = path_match[1]
        rest_of_args = path_match[2]
        parse_args(rest_of_args)
        span_name = name_span(program_name)
        start_us = sprintf("%.0f", timestamp * 1000000)

        data[1] = "type";       data[2] = "execve"
        data[3] = "name";       data[4] = span_name
        data[5] = "start_us";   data[6] = start_us
        data[7] = "pid";        data[8] = pid
        data[9] = "strace";     data[10] = strace_log
    }
}
