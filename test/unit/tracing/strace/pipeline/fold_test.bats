#!/usr/bin/env bats

source test/test_helper.bash

pipeline_dir="src/tracing/strace/pipeline/"
STREAMING_SCRIPT=$pipeline_dir/300_streaming_hierarchy.jq

function generate_json_stream() {
    local -a events=("$@")

    # This associative array mimics the awk script's 'ppid_map'
    # to track parent/child relationships.
    declare -A ppid_map

    local timestamp=1.0

    # Loop while there are elements in the array
    while [ ${#events[@]} -gt 0 ]; do
        local pid="${events[0]}"
        local type="${events[1]}"
        local name="${events[2]}"
        shift 3

        # Get the parent_pid for this PID.
        # Defaults to the string "null" if not found.
        local parent_pid="${ppid_map[$pid]:-null}"
        local child_pid="null"

        if [ "$type" == "clone" ]; then
            # If it's a clone, the 4th element is the child_pid
            child_pid="${events[0]}"
            shift 1

            # CRITICAL: Set the parent_pid for the *child*
            # so its 'execve' event will be linked correctly.
            ppid_map[$child_pid]="$pid"
        fi

        # Use jq -n (null input) to construct a JSON object
        # from the bash variables.
        jq -n \
           --arg pid "$pid" \
           --arg type "$type" \
           --arg name "$name" \
           --arg ts "$timestamp" \
           --arg ppid_str "$parent_pid" \
           --arg cpid_str "$child_pid" \
           '{
                "pid": $pid,
                "type": $type,
                "name": $name,
                "start_us": ($ts | tonumber),
                "parent_pid": (if $ppid_str == "null" then null else $ppid_str end),
                "child_pid": (if $cpid_str == "null" then null else $cpid_str end)
            }'

        # Increment timestamp to ensure events are ordered
        timestamp=$(echo "$timestamp + 1.0" | bc)
    done
}

function generate_single_event_json() {
    local pid="$1"
    local type="$2"
    local name="$3"
    local child_pid="$4" # Will be "null" if not a clone
    local parent_pid="$5" # Will be "null" if root
    local timestamp="$6"

    jq -n \
       --arg pid "$pid" \
       --arg type "$type" \
       --arg name "$name" \
       --arg ts "$timestamp" \
       --arg ppid_str "$parent_pid" \
       --arg cpid_str "$child_pid" \
       '{
            "pid": $pid,
            "type": $type,
            "name": $name,
            "start_us": ($ts | tonumber),
            "parent_pid": (if $ppid_str == "null" then null else $ppid_str end),
            "child_pid": (if $cpid_str == "null" then null else $cpid_str end)
        }'
}

function run_and_test() {
    # $pipeline_dir is set at the top of the bats file
    if [[ -z "$pipeline_dir" ]]; then
        echo "HELPER_ERROR: 'run_and_test' requires \$pipeline_dir to be set." >&2
        return 1
    fi
    # $STREAMING_SCRIPT is also set at the top
    if [[ -z "$STREAMING_SCRIPT" ]]; then
        echo "HELPER_ERROR: 'run_and_test' requires \$STREAMING_SCRIPT to be set." >&2
        return 1
    fi
    # Get just the script *name* from the full path
    local script_name
    script_name=$(basename "$STREAMING_SCRIPT" .jq)


    local i=1
    # The initial *internal state* for the reducer
    local internal_state_json='{"tree":{},"paths":{}}'

    declare -A ppid_map
    local timestamp=1.0

    while true; do
        local event_var_name="event$i"
        local state_var_name="state$i"

        # Check if eventN variable is defined
        if ! declare -p "$event_var_name" &>/dev/null; then
            if (( i == 1 )); then
                echo "HELPER_ERROR: 'run_and_test' found no 'event1' variable." >&2
                return 1
            fi
            break # No more events, all steps passed
        fi

        # Get the eventN array content
        local event_array_def
        event_array_def=$(declare -p "$event_var_name")
        eval "local current_event=${event_array_def#*=}"

        # Get the expected *tree* JSON string (it's empty if not set)
        local expected_tree_json="${!state_var_name:-}"

        local pid="${current_event[0]}"
        local type="${current_event[1]}"
        local name="${current_event[2]}"

        local parent_pid="${ppid_map[$pid]:-null}"
        local child_pid="null"

        if [ "$type" == "clone" ]; then
            child_pid="${current_event[3]}"
            ppid_map[$child_pid]="$pid"
        fi

        # 1. Generate the single event JSON
        local event_json
        event_json=$(generate_single_event_json \
            "$pid" "$type" "$name" "$child_pid" "$parent_pid" "$timestamp")

        # 2. Run the `fold_event` function using the BATS `run` helper
        # We pass the full command string to `run`
        run jq -n \
            --argjson state "$internal_state_json" \
            --argjson event "$event_json" \
            -L "$pipeline_dir" \
            "include \"$script_name\"; fold_event(\$state; \$event)"

        # 3. Assert the `jq` call succeeded
        assert_success

        # 6. Carry the *full* state for the next loop
        internal_state_json="$output"

        # 4. Get the *tree* part of the new state
        # `$output` now contains the *full* internal state from the `run` command
        local actual_tree_json
        actual_tree_json=$(echo "$output" | jq -c .tree)

        # 5. Compare the extracted tree *if* stateN was defined
        #    (even if it was defined as an empty string)
        if declare -p "$state_var_name" &>/dev/null; then

            # We trust assert_json_match to handle all errors.
            assert_json_match "$actual_tree_json" "$expected_tree_json"
        fi

        # 7. Increment timestamp *in this scope*
        timestamp=$(echo "$timestamp + 1.0" | bc)

        i=$((i + 1))
    done

    return 0 # All steps passed
}



@test "simple (sparse match)" {
  event1=(100 execve "foo")
  state1='{"100":{"name":"foo","type":"execve"}}'

  event2=(100 clone "clone_101" 101)
  state2='{"100":{"name":"foo","children":{"101":{"name":"clone_101"}}}}'

  event3=(101 clone "clone_102" 102)
  state3='     {
       "100": {
         "name": "foo",
         "pid": "100",
         "type": "execve",
         "start_us": 1.0,
         "children": {
           "101": {
             "name": "clone_101",
             "pid": "100",
             "type": "clone",
             "start_us": 2.0,
             "children": {
               "102": {
                 "name": "clone_102",
                 "pid": "101",
                 "type": "clone",
                 "start_us": 3.0,
                 "children": {}
               }
             }
           }
         }
       }
     }
'

  run_and_test
}

@test "skip intermediate state" {

  event1=(100 execve "foo")
  event2=(100 clone "clone_101" 101)
  state2='{"100":{"name":"foo","pid":"100","type":"execve","start_us":1.0,"children":{"101":{"name":"clone_101","pid":"100","type":"clone","start_us":2.0,"children":{}}}}}'

  run_and_test
}
