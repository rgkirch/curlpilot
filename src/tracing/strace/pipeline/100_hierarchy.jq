# This script processes an ARRAY of JSON "span fragments"
# and restructures them into a single hierarchical JSON object
# based on the pid/parent_pid relationship from 'clone' events.
#
# It is intended to be run with the --slurp (-s) flag.

# --- Main Script ---

# Slurp the entire input array of fragments
. as $all_fragments
|
# 1. Create a map of: pid -> [array of all fragments for that pid]
(
  $all_fragments
  | group_by(.pid)
  # Convert the array of groups into a single map object
  | map({(.[0].pid): .})
  | add
) as $data_map
|
# 2. Create a map of: parent_pid -> [array of unique child_pids]
(
  $all_fragments
  | reduce .[] as $fragment (
      {};
      # Only fragments with a 'parent_pid' (i.e., 'clone' events)
      # define the hierarchical structure.
      if $fragment.parent_pid != null then
        .[$fragment.parent_pid] += [$fragment.pid]
      else
        .
      end
    )
  # Ensure all child arrays contain unique PIDs, just in case
  | map_values(unique)
) as $child_map
|
# 3. Find the root PID(s)
(
  # Get all PIDs that have data
  ($data_map | keys) as $all_pids
  # Get all PIDs that are children of another PID
  | ($child_map | values | flatten | unique) as $all_child_pids

  # The root(s) are PIDs that exist but are not children of any other PID
  | $all_pids - $all_child_pids
) as $root_pids
|
# 4. Define a recursive function to build the tree
def build_tree($pid; $data_map; $child_map):
  {
    "pid": $pid,

    # 'fragments' will be an array of all raw log objects for this PID
    "fragments": $data_map[$pid] // [],

    # 'children' is an array of nodes built by recursing on this PID's children
    "children": (
      $child_map[$pid] // []
      | sort # Sort children by pid, as requested
      | map(build_tree(.; $data_map; $child_map))
    )
  }
;
# 5. Build a tree for *each* root PID found.
#    This results in an array of one or more trees.
(
  $root_pids
  | sort # Sort root pids for consistent output
  | map(build_tree(.; $data_map; $child_map))
)
