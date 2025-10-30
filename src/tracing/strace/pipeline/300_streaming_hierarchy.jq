# ==> 300_streaming_hierarchy.jq <==
#
# This script is a "library" file. It ONLY defines the
# functions used for building the hierarchy.
#

# --- Helper Functions ---
def new_span($event):
  {
    "name": $event.name,
    "pid": $event.pid,
    "type": $event.type,
    "start_us": $event.start_us,
    "children": {}
  };

# --- Reducer Function ---
# This is the core logic, isolated into a function.
# It takes the current state (which includes .tree and .paths)
# and a new event, and returns the new state.
def fold_event($state; $event):
  ($state.paths // {}) as $paths
  |
  ($paths[$event.pid] // null) as $parent_path
  |
  # Now, handle the event based on its type
  if $event.type == "execve" then
    (
      new_span($event) as $span_node
      | (
          if $parent_path == null then
            # This is a ROOT execve.
            # The path to this node's children is ["tree", pid, "children"]
            ["tree", $event.pid, "children"] as $new_path
            | $state
            # Set the node itself at ["tree", pid]
            | setpath($new_path[0:2]; $span_node)
            # Save the children path for this PID
            | setpath(["paths", $event.pid]; $new_path)
          else
            # This is a child execve, nesting under its parent span.
            # We use "execve" as the key in the children object.
            ($parent_path + ["execve"]) as $node_path
            | ($node_path + ["children"]) as $new_path
            | $state
            # Set the node at parent_path + ["execve"]
            | setpath($node_path; $span_node)
            # Update this PID's active path to the new node's children
            | setpath(["paths", $event.pid]; $new_path)
          end
        )
    )
  elif $event.type == "clone" then
    (
      new_span($event) as $span_node
      | ($event.child_pid) as $child_pid
      |
      # A clone always nests under its process's active span.
      # Its key in the children object is the child_pid.
      ($parent_path + [$child_pid]) as $node_path
      | ($node_path + ["children"]) as $new_path
      | $state
      # Set the new clone node
      | setpath($node_path; $span_node)
      # *CRITICAL*: Set the insertion path for the *child_pid*
      # to be this new clone node's children.
      | setpath(["paths", $child_pid]; $new_path)
    )
  else
    # Not a span-creating event, just pass the state through
    $state
  end;
