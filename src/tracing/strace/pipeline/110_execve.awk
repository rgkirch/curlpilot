#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

# This helper function parses exactly one quoted argument from the start
# of a string. It returns the argument and the remainder of the string
# via the 'result' array (which is passed by reference).
#
# @param arg_string The string to parse (e.g., "arg1", "arg2"]...)
# @param result      An array to store results:
#                   result[1] = the parsed argument (if found)
#                   result[2] = the remainder of the string
# @return            1 if an argument was successfully parsed,
#                   0 if the end bracket or an error was found.
function _parse_single_arg(arg_string, result,     # Local vars
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

        # gawk sets RLENGTH to the length of the *full match* (e.g., "arg1")
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
# @return            The remainder of the string *after* the closing bracket.
function parse_args(arg_string,     parse_result, single_arg) {
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

function name_span(program_name, args_string,    i, arg, primary_action_str) {

    if (program_name == "bats-exec-file") {
        # Find the first argument that ends in .bats
        for (i = 2; i in _parsed_args_global; i++) {
            arg = _parsed_args_global[i]
            if (arg ~ /\.bats$/) {
                return arg # Return the .bats file path
            }
        }
        return program_name " " args_string
    } else {
        return ""
    }
}

{
    if ($1 == "execve") {
        pid = $2
        timestamp = $4
        args_string = $5 # This is the string with all the execve arguments.
        strace_log = $NF
        debug_text = ""

        # 1. Extract the program basename and the rest of the args string.
        if (match(args_string, /^"[^"]*\/([^\/"]+)", (.*)/, path_match)) {
            program_name = path_match[1]
            rest_of_args = path_match[2] # e.g., ["arg1", "arg2"], 0xABC ...

            # 2. Isolate and parse the argument array.
            # This function call populates _parsed_args_global as a side-effect.
            parse_args(rest_of_args)
            span_name = name_span(program_name, args_string)
            start_us = sprintf("%.0f", timestamp * 1000000)
            print "json", "type", $1, "name", span_name, "start_us", start_us, "pid", pid, "strace", strace_log, "debug_text", debug_text

        } else {
            print "unmatched", $0
        }

    } else {
        # Pass through any other lines (like "clone", "exit_group", etc.) unmodified.
        print $0
    }
}
