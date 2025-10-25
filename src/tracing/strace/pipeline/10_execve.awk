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
    #    NOTE: We have removed the ",? *(.*)" part from the regex!
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
function parse_args(arg_string,     # Local variables below
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

# --- NEW FUNCTION ---
# Iterates through global args and finds the best "primary action"
# based on special command-specific rules.
function find_primary_action(program_name,    # Local vars
                             i, arg, primary_action_str) {

    # --- Special handling for 'bats-exec-file' ---
    if (program_name == "bats-exec-file") {
        # Find the first argument that ends in .bats
        for (i = 2; i in _parsed_args_global; i++) {
            arg = _parsed_args_global[i]
            if (arg ~ /\.bats$/) {
                return arg # Return the .bats file path
            }
        }
        # If no .bats file found, return empty.
        return ""
    }

    # --- Add other special cases here ---
    # else if (program_name == "gcc") {
    #     # find first .c file, etc.
    # }

    # --- NEW Default Heuristic ---
    # For all other commands, concatenate all non-flag arguments.
    else {
        primary_action_str = ""
        for (i = 2; i in _parsed_args_global; i++) {
            arg = _parsed_args_global[i]
            gsub(/^[ \t]+|[ \t]+$/, "", arg) # Trim whitespace.

            if (substr(arg, 1, 1) != "-") {
                # This is a non-flag argument, add it to the string.
                primary_action_str = (primary_action_str == "" ? "" : primary_action_str " ") arg
            }
        }
        return primary_action_str
    }

    return "" # No suitable primary action found
}

# --- NEW FUNCTION ---
# Iterates through global args and concatenates all flags.
function find_flags(program_name,    # Local vars
                     i, arg, flags_str) {

    # --- Special handling for 'bats-exec-file' ---
    if (program_name == "bats-exec-file") {
        return "" # User doesn't want to see flags for this command
    }
    # --- End special handling ---

    flags_str = ""
    for (i = 2; i in _parsed_args_global; i++) {
        arg = _parsed_args_global[i]
        gsub(/^[ \t]+|[ \t]+$/, "", arg) # Trim whitespace.

        if (substr(arg, 1, 1) == "-") {
            flags_str = (flags_str == "" ? "" : flags_str ", ") arg
        }
    }
    return flags_str
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
            # This function call populates _parsed_args_global as a side-effect.
            parse_args(rest_of_args)

            # Add debug info about the parsed args.
            for (j = 1; j <= length(_parsed_args_global); j++) {
                debug_text = debug_text ", _parsed_args_global[" j "]: '" _parsed_args_global[j] "'"
            }

            # 3. --- REPLACED LOGIC ---
            # Find the primary action and flags using the new functions.
            primary_action = find_primary_action(program_name)
            flags_string = find_flags(program_name) # <-- Pass program_name
            # --- END REPLACED LOGIC ---

            # 4. If primary_action looks like a SINGLE path, extract the basename.
            debug_text = debug_text ", primary_action before sub: '" primary_action "'"
            # Only run sub() if it's a path AND not a multi-arg string
            if (primary_action ~ /\// && primary_action !~ / /) {
                sub(/.*\//, "", primary_action)
            }
            debug_text = debug_text ", primary_action after sub: '" primary_action "'"

            # 5. Construct the final, meaningful span name from the parts.
            span_name = program_name
            if (primary_action != "") {
                span_name = span_name ": " primary_action
            }
            if (flags_string != "") {
                span_name = span_name " [ " flags_string " ]"
            }
            span_name = span_name " <" pid ">"

            # 6. Convert timestamp to microseconds for start_us.
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
