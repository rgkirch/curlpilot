#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    OFS = FS = "\037"
}

# This custom function iteratively parses a string of quoted arguments and
# populates a global array named `_parsed_args_global`.
#
# @param arg_string The raw string to parse (e.g., `"arg1", "arg2, with comma"`)
function parse_args(arg_string,   # Local variables below
                    match_arr, single_arg) {
    # Clear the global array of any old data before populating it.
    delete _parsed_args_global

    # This regex is a robust pattern for matching a complete quoted string
    # while correctly handling any escaped quotes (\") inside it.
    escaped_quote_re = /"([^"\\]*(?:\\.[^"\\]*)*)"/

    # The regex for sub() is the same but without the capture group.
    # It removes the matched string, the optional trailing comma, and spaces.
    sub_re = /"[^"\\]*(?:\\.[^"\\]*)*",? */

    # Loop as long as we can find a quoted string in the remaining arg_string.
    while (match(arg_string, escaped_quote_re, match_arr)) {
        # match_arr[1] contains the content inside the quotes.
        single_arg = match_arr[1]
        # Populate the global array.
        _parsed_args_global[length(_parsed_args_global) + 1] = single_arg

        # After finding an argument, remove it and any following comma/space
        # from the string so the next iteration can find the next argument.
        sub(sub_re, "", arg_string)
    }
}

{
    # We only want to process lines that the previous script tagged as "execve".
    if ($1 == "execve") {
        # Assign the raw fields to named variables for clarity.
        pid = $2
        timestamp = $4
        args_string = $5 # This is the string with all the execve arguments.
        strace_log = $7

        # 1. Use your corrected regex to extract the program basename and the rest of the args.
        #    Using '[^"]*' instead of '[^"]+' correctly handles paths like "/foo".
        if (match(args_string, /^"[^"]*\/([^/"]+)", (.*)/, path_match)) {
            program_name = path_match[1]
            rest_of_args = path_match[2]

            # 2. Isolate and parse the argument array using our new robust function.
            primary_action = ""
            flags_string = ""
            if (match(rest_of_args, /\[(.*)\]/, arg_array_match)) {
                # Get the content inside the brackets.
                arg_content = arg_array_match[1]

                # Call the function. It will populate the global `_parsed_args_global` array.
                parse_args(arg_content)

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
                        primary_action = arg
                    }
                }
            }

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

            print "json", "name", span_name, "start_us", start_us, "pid", pid, "strace", strace_log

        } else {
            print $0
        }

    } else {
        # Pass through any other lines (like "clone", "exit_group", etc.) unmodified.
        print $0
    }
}
