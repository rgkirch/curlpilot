# ==> process_lib.jq <==

# --- From 201_link_spans.jq ---
def link_spans_recursive($node):
  ($node.fragments | map(
    if .type == "clone" or .type == "execve" then
      . + {span_id: "\($node.pid).\(.fragment_index)"}
    else . end
  )) as $new_fragments
  | ($new_fragments | map(select(.span_id != null) | {id: .span_id, start: .start_us})) as $parent_span_list
  | ($node.children | map(
      . as $child_node
      | ($child_node.fragments[0].start_us) as $child_start_time
      | ($parent_span_list | map(select(.start < $child_start_time)) | last) as $parent_span
      | ($child_node + {parent_span_id: ($parent_span.id // null)}) as $linked_child
      | link_spans_recursive($linked_child)
    )) as $new_children
  | $node + {fragments: $new_fragments, children: $new_children}
;

# --- From 202_with_collapsed_stack.jq ---
def build_span_map($node):
  ($node.parent_span_id) as $parent_id
  | ($node.fragments
    | map(
        select(.span_id)
        | {key: .span_id, value: {name: .name, parent: $parent_id}}
      )
    | from_entries
  ) as $local_spans
  | ($node.children | map(build_span_map(.)) | add) as $child_spans
  | $local_spans + $child_spans
;

def get_stack($span_id; $span_map):
  ($span_map[$span_id]) as $span
  | ($span.parent) as $parent_id
  | (if $parent_id != null and ($span_map | has($parent_id)) then
      get_stack($parent_id; $span_map)
    else [] end)
  + [$span.name]
;

def add_stack_recursive($node; $span_map):
  ($node.children | map(add_stack_recursive(.; $span_map))) as $new_children
  | ($node.fragments | map(
     if .span_id then
       . + { "collapsed_stack": (get_stack(.span_id; $span_map) | join(";")) }
     else . end
  )) as $new_fragments
  | $node + {fragments: $new_fragments, children: $new_children}
;

# --- From 203_with_durations.jq ---
def add_duration_recursive($node):
  ($node.children | map(add_duration_recursive(.))) as $new_children
  | (
    $node.fragments as $frags
    | $frags | map(
      . as $fragment
      | if .span_id then
        (
          ($frags
            | map(
              select(
                .fragment_index > $fragment.fragment_index and
                (.type == "clone" or .type == "execve" or .type == "exited")
              )
            )
            | .[0]
          ) as $next_event
          | ($next_event.start_us // $next_event.end_us) as $end_time_string
          | ($fragment.start_us) as $start_time_string
          | (if $end_time_string then ($end_time_string | tonumber) else null end) as $end_time
          | (if $start_time_string then ($start_time_string | tonumber) else null end) as $start_time
          | (if $end_time and $start_time then $end_time - $start_time else null end) as $duration
          | $fragment + { "duration": $duration }
        )
      else
        $fragment
      end
    )
  ) as $new_fragments
  | $node + {fragments: $new_fragments, children: $new_children}
;

# --- From 204_as_collapsed_stack.jq ---
def emit_stacks($node):
  (
    $node.fragments
    | map(
        select((.collapsed_stack != null) and (.duration != null))
        | "\(.collapsed_stack) \(.duration)"
      )
  ) as $local_stacks
  | (
    $node.children | map(emit_stacks(.)) | flatten
  ) as $child_stacks
  | $local_stacks + $child_stacks
;
