# This script processes the hierarchical output of create_collapsed_stacks.jq
# and *enriches* it further. It walks the tree and adds a "duration"
# (in microseconds) to every fragment that has a "span_id".
#
# It leaves the hierarchy intact.
#
# It expects the array of trees from create_collapsed_stacks.jq as input.


# --- Helper: Recursively Add Durations to Nodes ---
# This function walks the tree and adds a "duration"
# key to every fragment that has a "span_id".
def add_duration_recursive($node):
  # 1. Recurse on children first.
  ($node.children | map(add_duration_recursive(.))) as $new_children
  |
  # 2. Process this node's fragments.
  (
    $node.fragments as $frags # Alias for the full fragments array
    | $frags | map(
        . as $fragment # The current fragment we are mapping over
        |
        # If this fragment is a span start (we check for span_id)...
        if .span_id then
          (
            # ...find the *next* event that ends this span.
            # This is the next 'clone', 'execve', or 'exited' event.
            (
              $frags
              | map(
                  select(
                    .fragment_index > $fragment.fragment_index and
                    (.type == "clone" or .type == "execve" or .type == "exited")
                  )
                )
              | .[0] # Get the very first one
            ) as $next_event
            |
            # Get the end time string safely.
            ($next_event.start_us // $next_event.end_us) as $end_time_string
            |
            # Get the start time string safely.
            ($fragment.start_us) as $start_time_string
            |
            # Convert to numbers *only if they exist*.
            (if $end_time_string then ($end_time_string | tonumber) else null end) as $end_time
            |
            (if $start_time_string then ($start_time_string | tonumber) else null end) as $start_time
            |
            # Calculate duration only if both numbers are valid.
            (if $end_time and $start_time then $end_time - $start_time else null end) as $duration
            |
            # Add the duration
            $fragment + { "duration": $duration }
          )
        else
          # ...otherwise, leave it as-is.
          $fragment
        end
      )
  ) as $new_fragments
  |
  # 3. Return the modified node, preserving the hierarchy.
  $node + {fragments: $new_fragments, children: $new_children}
;


# --- Main Script ---

# 1. Slurp the input tree array
. as $tree
|
# 2. Apply the recursive function to add durations to the hierarchy
$tree | map(add_duration_recursive(.))
