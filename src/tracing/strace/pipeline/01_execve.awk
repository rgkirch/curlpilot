#!/usr/bin/gawk -f

BEGIN {
    # Set the Input Field Separator to match the previous script's OFS.
    FS = "\037"
}

{
    # We only want to process lines that the previous script tagged as "execve".
    if ($1 == "execve") {
        # --- This is the logic you asked for ---

        # Assign the raw fields to named variables for clarity.
        pid = $2
        args_string = $6 # This is the string with all the execve arguments.

        # 1. Extract the program name from the first quoted string.
        if (match(args_string, /^"[^"]*\/([^/"]+)", (.*)/, path_match)) {
            program_name = path_match[1]

            # 2. Isolate and parse the argument array (the part in [...]).
            primary_action = ""
            flags_string = ""
            if (match(path_match[2], /\[(.*)\]/, arg_array_match)) {
                # Get the content inside the brackets.
                arg_content = arg_array_match[1]
                gsub(/"/, "", arg_content)      # Remove all quotes.
                split(arg_content, arg_list, /, /) # Split arguments into an array.

                # Loop through the arguments to find the primary action and all flags.
                # We start at index 2 because index 1 is just the program name again.
                for (i = 2; i in arg_list; i++) {
                    arg = arg_list[i]
                    gsub(/^[ \t]+|[ \t]+$/, "", arg) # Trim leading/trailing whitespace.

                    if (substr(arg, 1, 1) == "-") {
                        # If it starts with a '-', it's a flag.
                        flags_string = (flags_string == "" ? "" : flags_string ", ") arg
                    } else if (primary_action == "") {
                        # This is the first argument that is NOT a flag, so we'll
                        # call it the primary action.
                        primary_action = arg
                    }
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

        # Print the new span name as a key-value pair, separated by our OFS.
        print "span_name\037" span_name

    } else {
        # Pass through any other lines (like "clone", "exit_group", etc.) unmodified.
        print $0
    }
}
