# This script converts the array of "stitched spans" from stitch_spans.jq
# into the same array, but with a "collapsed_stack" key added
# to each span object.
#
# It assumes --slurp (-s) was used on the *previous* script, so it
# expects a single flat array of span objects as its input.

# --- Helper Function ---
# Recursively walks up the parent_pid chain to build the stack.
# $pid: The pid of the span to start from
# $map: The object mapping all pids to their spans
def get_stack($pid; $map):
  # Get the span for the current PID
  ($map[$pid]) as $span
  # Get the parent PID
  | ($span.parent_pid) as $ppid

  # If the parent_pid is not null AND exists in the map, get its stack first.
  # Otherwise, start with an empty array (we are a root).
  | (if $ppid != null and ($map | has($ppid)) then get_stack($ppid; $map) else [] end)

  # Add our own name to the stack
  + [$span.name]
;

# --- Main Script ---

# 1. Filter out any orphan end events (which have no start_us)
#    and calculate the duration (weight) for all valid spans.
map(select(.start_us != null and .end_us != null) | .duration = ((.end_us | tonumber) - (.start_us | tonumber))) as $completed_spans

# 2. Create an object (a map) for fast lookups by PID
| INDEX($completed_spans[]; .pid) as $spans_map

# 3. Map over the completed spans array.
#    For each span, add a new "collapsed_stack" key.
#    The value is the semi-colon-joined stack string.
| $completed_spans
| map(
    . + { "collapsed_stack": (get_stack(.pid; $spans_map) | join(";")) }
  )
