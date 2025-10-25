# This script processes the hierarchical output of add_durations.jq
# and "flattens" it into the final collapsed stack format.
#
# It outputs one string per span, with the duration at the end.
# e.g. "stack;frame 12345"
#
# It expects the array of trees from add_durations.jq as input.


# --- Helper: Recursively Find and Emit Stacks ---
# This function walks the tree and returns a flat array
# of formatted stack strings.
def emit_stacks($node):
  # 1. Find all valid spans in *this* node's fragments.
  #    A valid span has both a stack and a duration.
  (
    $node.fragments
    | map(
        select(
          (.collapsed_stack != null) and (.duration != null)
        )
        # Format the final string
        | "\(.collapsed_stack) \(.duration)"
      )
  ) as $local_stacks
  |
  # 2. Recurse into children and get their stacks.
  (
    $node.children | map(emit_stacks(.)) | flatten
  ) as $child_stacks
  |
  # 3. Return a flat array of this node's stacks + all children's stacks.
  $local_stacks + $child_stacks
;


# --- Main Script ---

# 1. Slurp the input tree array
. as $tree
|
# 2. Apply the recursive emitter to all root nodes.
$tree
| map(emit_stacks(.))
# 3. Flatten the resulting array of arrays.
| flatten
# 4. Output each string on its own line.
| .[]
