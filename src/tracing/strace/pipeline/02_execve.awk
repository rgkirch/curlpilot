#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"

    # This regex captures the arg (group 1) and the rest of the string (group 2).
    # It handles the optional comma and spaces between.
    arg_and_rest_re = /"([^"\\]*(?:\\.[^"\\]*)*)",? *(.*)/
}

# This helper function parses exactly one quoted argument from the start
# of a string. It returns the argument and the remainder of the string
# via the 'result' array (which is passed by reference).
#
# @param arg_string The string to parse (e.g., "arg1", "arg2"]...)
# @param result     An array to store results:
#                   result[1] = the parsed argument (if found)
#                   result[2] = the remainder of the string
# @return           1 if an argument was successfully parsed,
#                   0 if the end bracket or an error was found.
function _parse_single_arg(arg_string, result,    # Local vars
                           match_arr) {
    # Clear previous results
    delete result

    # 1. Trim whitespace before the next token.
    sub(/^[ \t]+/, "", arg_string)

    # 2. Check if the next token is the closing bracket.
    if (substr(arg_string, 1, 1) == "]") {
        result[1] = ""
        result[2] = substr(arg_string, 2) # Remainder is after ']'
        return 0 # Status code for "stop"
    } else if (match(arg_string, arg_and_rest_re, match_arr)) {
        # 3. If not a ']', try to match a quoted argument and the rest of the string.
        # match_arr[1] is the arg, match_arr[2] is the rest of the string.
        result[1] = match_arr[1]
        result[2] = match_arr[2]
        return 1 # Status code for "arg found"
    } else {
        # 4. No quoted string found, and not a ']'
        # This is a malformed array or we're done.
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
# @return           The remainder of the string *after* the closing bracket.
function parse_args(arg_string,    # Local variables below
                    parse_result, single_arg) {
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

{
    # We only want to process lines that the previous script tagged as "execve".
    if ($1 == "execve") {
        # Assign the raw fields to named variables for clarity.
        pid = $2
        timestamp = $4
        args_string = $5 # This is the string with all the execve arguments.
        strace_log = $7
        debug_text = ""

        # 1. Extract the program basename and the rest of the args string.
        if (match(args_string, /^"[^"]*\/([^\/"]+)", (.*)/, path_match)) {
            program_name = path_match[1]
            rest_of_args = path_match[2] # e.g., ["arg1", "arg2"], 0xABC ...

            # 2. Isolate and parse the argument array.
            # parse_args now handles finding the [ ... ] block,
            # populates _parsed_args_global, and returns the rest of the line.
            primary_action = ""
            flags_string = ""

            # This function call populates _parsed_args_global as a side-effect.
            parse_args(rest_of_args)

            # Add debug info about the parsed args.
            for (j = 1; j <= length(_parsed_args_global); j++) {
                debug_text = debug_text ", _parsed_args_global[" j "]: '" _parsed_args_global[j] "'"
            }

            # Loop through the globally populated array to find the primary action and all flags.
            # We start at index 2 because index 1 is just the program name again.
            for (i = 2; i in _parsed_args_global; i++) {
                arg = _parsed_args_global[i]
                gsub(/^[ \t]+|[ \t]+$/, "", arg) # Trim leading/trailing whitespace.

                if (substr(arg, 1, 1) == "-") {
                    # If it starts with a '-', it's a flag.
                    flags_string = (flags_string == "" ? "" : flags_string ", ") arg
                } else if (primary_action == "") {
                    # This is the first non-flag argument; call it the primary action.
                    primary_string = arg
                }
            }

            # If primary_action looks like a path, extract the basename.
            debug_text = debug_text ", primary_action before sub: '" primary_action "'"
            if (primary_action ~ /\//) {
                sub(/.*\//, "", primary_action)
            }
            debug_text = debug_text ", primary_action after sub: '" primary_action "'"

            # 3. Construct the final, meaningful span name from the parts.
            span_name = program_name
            if (primary_action != "") {
                span_name = span_name ": " primary_action
            }
            if (flags_string != "") {
                span_name = span_name " [ " flags_string " ]"
            }
            span_name = span_name " <" pid ">"

            # 4. Convert timestamp to microseconds for start_us.
            start_us = sprintf("%.0f", timestamp * 1000000)

            print "json", "name", span_name, "start_us", start_us, "pid", pid, "strace", strace_log, "debug_text", debug_text

        } else {
            # Pass through if the initial path regex didn't match.
            print $0
        }

    } else {
        # Pass through any other lines (like "clone", "exit_group", etc.) unmodified.
        print $0
    }
}
