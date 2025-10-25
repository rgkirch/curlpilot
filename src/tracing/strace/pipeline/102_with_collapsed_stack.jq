# This script processes the hierarchical output of link_spans.jq
# and *enriches* it. It walks the tree and adds a "collapsed_stack"
# string to every fragment that has a "span_id".
#
# It leaves the hierarchy intact for further processing.
#
# It expects the array of trees from link_spans.jq as input.


# --- Helper 1: Build a Map of all Spans ---
# Recursively walks the tree to build a "phone book" of all spans.
# Format: { "span_id": { "name": "...", "parent": "parent_span_id" }, ... }
def build_span_map($node):
  # 1. Get the parent_span_id for this node.
  ($node.parent_span_id) as $parent_id
  |
  # 2. Get all spans defined *within this node's fragments*.
  #    Their parent is the node's parent.
  ($node.fragments
    | map(
        select(.span_id)
        | {key: .span_id, value: {name: .name, parent: $parent_id}}
      )
    | from_entries
  ) as $local_spans
  |
  # 3. Recurse into children and add their spans.
  ($node.children | map(build_span_map(.)) | add) as $child_spans
  |
  # 4. Combine and return.
  $local_spans + $child_spans
;


# --- Helper 2: Recursively Get Stack String ---
# Walks up the $span_map to build the stack for a single span_id.
def get_stack($span_id; $span_map):
  (
    # 1. Get this span's info from the map
    $span_map[$span_id]
  ) as $span
  |
  # 2. Get its parent's ID
  ($span.parent) as $parent_id
  |
  # 3. If the parent exists in the map, get its stack first (recurse).
  #    Otherwise, start with an empty stack (we are a root span).
  (
    if $parent_id != null and ($span_map | has($parent_id)) then
      get_stack($parent_id; $span_map)
    else
      []
    end
  )
  # 4. Add our own name to the stack
  + [$span.name]
;


# --- Helper 3: Recursively Add Stacks to Nodes ---
# This function walks the tree and adds a "collapsed_stack"
# key to every fragment that has a "span_id".
def add_stack_recursive($node; $span_map):
  # 1. Recurse on children first.
  ($node.children | map(add_stack_recursive(.; $span_map))) as $new_children
  |
  # 2. Process this node's fragments.
  ($node.fragments | map(
    # If this fragment is a span start...
    if .span_id then
      # ...add its full collapsed stack.
      . + {
        "collapsed_stack": (
          get_stack(.span_id; $span_map) | join(";")
        )
      }
    else
      # ...otherwise, leave it as-is.
      .
    end
  )) as $new_fragments
  |
  # 3. Return the modified node, preserving the hierarchy.
  $node + {fragments: $new_fragments, children: $new_children}
;


# --- Main Script ---

# 1. Slurp the input tree array
. as $tree
|
# 2. Build the global "phone book" of all spans
($tree | map(build_span_map(.)) | add) as $span_map
|
# 3. Apply the recursive function to add stacks to the hierarchy
$tree | map(add_stack_recursive(.; $span_map))
