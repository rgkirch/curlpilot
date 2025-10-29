# ==> 300_streaming_hierarchy.jq <==
#
# This script is a "library" file. It ONLY defines the
# functions used for building the hierarchy.
#

# --- Helper Functions ---
def new_span($fragment):
  {
    "name": $fragment.name,
    "pid": $fragment.pid,
    "type": $fragment.type,
    "start_us": $fragment.start_us,
    "children": {}
  };

# --- Reducer Function ---
# This is the core logic, isolated into a function.
# It takes the current state (which includes .tree and .paths)
# and a new event, and returns the new state.
def fold_event($state; $fragment):

  # --- DEFENSIVE FIX ---
  # Ensure $state.paths is a valid object, even if $state is {}.
  # This defaults $paths to {} if $state.paths is null.
  ($state.paths // {}) as $paths
  |
  # Determine the path for this fragment's parent span
  (
    # A 'clone' event's parent is the active span of the parent *process*
    if $fragment.parent_pid then $paths[$fragment.parent_pid]
    # An 'execve' in a child process uses the path set by the 'clone'
    elif $fragment.pid != $fragment.parent_pid and ($paths | has($fragment.pid)) then $paths[$fragment.pid]
    # A root 'execve' or subsequent event in the *same* process
    else $paths[$fragment.pid] // null
    end
  ) as $parent_path
  |
  # Now, handle the fragment based on its type
  if $fragment.type == "execve" then
    (
      new_span($fragment) as $span_node
      | (
          if $parent_path == null then
            # This is a ROOT execve.
            # The path to this node's children is ["tree", pid, "children"]
            ["tree", $fragment.pid, "children"] as $new_path
            | $state
            # Set the node itself at ["tree", pid]
            | setpath($new_path[0:2]; $span_node)
            # Save the children path for this PID
            | setpath(["paths", $fragment.pid]; $new_path)
          else
            # This is a child execve, nesting under its parent span.
            # We use "execve" as the key in the children object.
            ($parent_path + ["execve"]) as $node_path
            | ($node_path + ["children"]) as $new_path
            | $state
            # Set the node at parent_path + ["execve"]
            | setpath($node_path; $span_node)
            # Update this PID's active path to the new node's children
            | setpath(["paths", $fragment.pid]; $new_path)
          end
        )
    )
  elif $fragment.type == "clone" then
    (
      new_span($fragment) as $span_node
      | ($fragment.child_pid) as $child_pid
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
      # Also update the parent's active path to point here now
      | setpath(["paths", $fragment.pid]; $new_path)
    )
  else
    # Not a span-creating event, just pass the state through
    $state
  end;
