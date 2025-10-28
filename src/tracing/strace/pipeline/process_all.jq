# ==> process_all.jq <==
#
# This script combines all logic from 201, 202, 203, and 204
# into a single jq invocation.
#
# It is intended to be run *after* 200_hierarchy.jq
#
# Usage:
#   ... | jq -f 200_hierarchy.jq | jq -r -f process_lib.jq -f process_all.jq

# Import all transformation functions
import "process_lib" as P;

# 1. Start with the tree output from 200_hierarchy.jq
.
# 2. Apply 201's logic
| map(P::link_spans_recursive(.)) as $linked_tree
|
# 3. Apply 202's logic
(
  ($linked_tree | map(P::build_span_map(.)) | add) as $span_map
  | $linked_tree | map(P::add_stack_recursive(.; $span_map))
) as $stacked_tree
|
# 4. Apply 203's logic
($stacked_tree | map(P::add_duration_recursive(.))) as $final_tree
|
# 5. Apply 204's logic
$final_tree
| map(P::emit_stacks(.))
| flatten
| .[]
