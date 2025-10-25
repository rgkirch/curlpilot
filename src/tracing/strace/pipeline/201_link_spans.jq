# This script processes the hierarchical output of build_tree.jq.
# It is intended to be run on the *array* output of that script.
#
# It walks the tree recursively to add:
# 1. `span_id` (e.g., "123.0") to each 'clone' and 'execve' fragment
#    using its fragment_index.
# 2. `parent_span_id` (e.g., "123.0") to each *child node* object, linking
#    it to the parent span that was active when the child was created.

# This recursive function processes a single node from the tree.
def link_spans_recursive($node):
  (
    # 1. Process this node's fragments to add `span_id`s
    # We map over the fragments, and if the type is "clone" or "execve",
    # we create the span_id using the node's pid and the fragment_index.
    ($node.fragments | map(
      if .type == "clone" or .type == "execve" then
        . + {span_id: "\($node.pid).\(.fragment_index)"}
      else
        .
      end
    )) as $new_fragments
    |
    # 2. Create a lookup list of the parent spans we just created.
    # This will be used to link children.
    (
      $new_fragments
      | map(select(.span_id != null) | {id: .span_id, start: .start_us})
    ) as $parent_span_list
    |
    # 3. Process all children
    (
      $node.children | map(
        . as $child_node
        |
        # Find the child's start time. This comes from its first fragment
        # (the 'clone' event), which is always at fragment_index: 0.
        ($child_node.fragments[0].start_us) as $child_start_time
        |
        # Find the parent span that was active when this child was created.
        # This is the *last* span that started *before* the child did.
        (
          $parent_span_list
          | map(select(.start < $child_start_time)) # Find all valid parent spans
          | last # Select the most recent one
        ) as $parent_span
        |
        # Add the 'parent_span_id' to the child node.
        # Use 'null' if no parent span was found (should only happen for roots).
        ($child_node + {parent_span_id: ($parent_span.id // null)}) as $linked_child
        |
        # 4. Recurse on the now-linked child.
        # This will process its fragments and its own children.
        link_spans_recursive($linked_child)
      )
    ) as $new_children
    |
    # 5. Return the fully modified node
    $node + {fragments: $new_fragments, children: $new_children}
  )
;

# --- Main Script ---
# Apply the recursive function to each root node in the input array.
map(link_spans_recursive(.))
