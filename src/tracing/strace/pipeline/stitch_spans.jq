# This script processes an ARRAY of JSON "span fragments" (start, end, and rename events)
# and "stitches" them together into a coherent set of spans.
#
# It is intended to be run with the --slurp (-s) flag.
#
# It correctly handles the case where a single PID (process) calls `execve`
# multiple times, turning that one PID into a *sequence* of spans,
# rather than flattening them into one.

# --- Main Script ---

# 1. Group the objects by their process ID ("pid").
#    (We assume --slurp is used, so the input is already an array)
group_by(.pid)

# 2. For each group (which is an array of fragments for a single PID)...
| map(
    # 2b. Sort all fragments for this PID chronologically.
    sort_by(.start_us // .end_us)

    # 2c. Iterate through the sorted fragments, "stitching" spans.
    #     We maintain a state object:
    #       .spans: The array of completed spans we've found.
    #       .open: The currently open span fragment, if any.
    | reduce .[] as $fragment (
        {spans: [], open: null};

        # --- STATE MACHINE LOGIC ---

        if $fragment.start_us != null then
          # This is a START event (clone or execve)

          if .open != null then
            # A span was already open! This new 'start' event (an execve)
            # must CLOSE the previous one.
            .spans += [
              .open
              # Use the new start time as the end time for the previous span
              | .end_us = $fragment.start_us
            ]
            # The new open span is the current fragment
            | .open = $fragment

          else
            # No span was open. This is the first one for this PID.
            .open = $fragment
          end

        elif $fragment.end_us != null then
          # This is an END event (exit, wait4, killed_by_signal)

          if .open != null then
            # A span is open. This event closes it.
            .spans += [
              # Merge the 'end' info into the 'open' span
              .open * $fragment
              # Keep the original start_us and name from the open span
              | .start_us = .open.start_us
              | .name = .open.name
            ]
            # The span is now closed.
            | .open = null

          else
            # This is an "orphan" end event (we never saw its start).
            # We can't do anything with it.
            .
          end

        else
          # This is some other fragment type we don't recognize.
          .
        end
      )
    # 2d. After iterating, 'state.spans' contains all *closed* spans.
    #     If a span was left open (process didn't exit), add it.
    | .spans + (if .open != null then [.open] else [] end)
  )

# 3. Flatten the array of arrays into a single, flat array of spans.
| flatten
