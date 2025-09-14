#!/bin/bash
set -euo pipefail

# curlpilot/clojure/core.sh

# A collection of Bash functions that mimic Clojure's hash map operations
# using jq for JSON manipulation. This version uses modern jq 1.6+ features.

# Creates a JSON object from a series of key-value arguments.
# Automatically converts values that look like numbers into JSON numbers.
# Usage: hash_map key1 "val1" key2 123 ...
hash_map() {
    if [ $(($# % 2)) -ne 0 ]; then
        echo "Error: hash_map requires an even number of arguments (key-value pairs)." >&2
        return 1
    fi

    local jq_args=()
    while [ "$#" -gt 0 ]; do
        jq_args+=(--arg "$1" "$2")
        shift 2
    done

    # Use $ARGS.named to build the object from command-line arguments.
    # Then, pipe to map_values to convert any values that look like
    # numbers (e.g., "30") into actual JSON numbers (e.g., 30).
    jq -n '$ARGS.named | map_values(tonumber? // .)' "${jq_args[@]}"
}

# Gets a value from a JSON object by its key.
# Usage: get '{"a": 1}' "a"
get() {
    local json_obj="$1"
    local key="$2"
    echo "$json_obj" | jq -r --arg key "$key" '.[$key]'
}

# Gets a value from a nested JSON object using a path of keys.
# Usage: get_in '{"a": {"b": 2}}' "a" "b"
get_in() {
    local json_obj="$1"
    shift
    local path_jq=""
    for key in "$@"; do
        path_jq+="[\"$key\"]"
    done
    echo "$json_obj" | jq -r ".$path_jq"
}

# Associates a key-value pair with a JSON object.
# The value should be a valid JSON literal (e.g., '"a string"', 123, true).
# Usage: assoc '{"a": 1}' "b" '"new string"'
# Usage: assoc '{"a": 1}' "c" 2
assoc() {
    local json_obj="$1"
    local key="$2"
    local value="$3"
    echo "$json_obj" | jq --arg key "$key" --argjson value "$value" '. + {($key): $value}'
}

# Associates a value in a nested structure.
# The value should be a valid JSON literal (e.g., '"a string"', 123, true).
# Usage: assoc_in '{"a": {"b": 2}}' "a" "c" 3
assoc_in() {
    local json_obj="$1"
    shift
    local value="${@: -1}" # last argument is the value
    local path_keys=("${@:1:$#-1}")

    local path_jq=""
    for key in "${path_keys[@]}"; do
        path_jq+="[\"$key\"]"
    done

    echo "$json_obj" | jq --argjson val "$value" ".${path_jq} = \$val"
}


# Dissociates a key from a JSON object.
# Usage: dissoc '{"a": 1, "b": 2}' "b"
dissoc() {
    local json_obj="$1"
    local key_to_remove="$2"
    echo "$json_obj" | jq --arg key "$key_to_remove" 'del(.[$key])'
}

# Dissociates a key from a nested JSON object.
# Usage: dissoc_in '{"a": {"b": 2, "c": 3}}' "a" "c"
dissoc_in() {
    local json_obj="$1"
    shift
    local path_jq=""
    for key in "$@"; do
        path_jq+="[\"$key\"]"
    done
    echo "$json_obj" | jq "del(.$path_jq)"
}


# --- Examples ---
echo "--- hash_map ---"
my_map=$(hash_map "name" "John Doe" "age" "30" "city" "New York" "is_member" "true")
echo "Created map: $my_map"
echo

echo "--- get ---"
name=$(get "$my_map" "name")
echo "Get 'name': $name"
echo

echo "--- get_in (simple) ---"
age=$(get_in "$my_map" "age")
echo "Get 'age': $age"
echo

echo "--- assoc ---"
# Note the extra quotes to make "Developer" a valid JSON string for --argjson
my_map_updated=$(assoc "$my_map" "occupation" '"Developer"')
my_map_updated=$(assoc "$my_map_updated" "zip" 10001) # Numbers don't need extra quotes
echo "Associated 'occupation' and 'zip': $my_map_updated"
echo

echo "--- dissoc ---"
my_map_dissoc=$(dissoc "$my_map_updated" "city")
echo "Dissociated 'city': $my_map_dissoc"
echo

echo "--- Creating a nested map for further tests ---"
nested_map='{"user": {"details": {"name": "Jane", "age": 28}, "roles": ["admin", "editor"]}}'
echo "Nested map: $nested_map"
echo

echo "--- get_in (nested) ---"
nested_name=$(get_in "$nested_map" "user" "details" "name")
echo "Get 'user.details.name': $nested_name"
echo

echo "--- assoc_in ---"
nested_map_assoc=$(assoc_in "$nested_map" "user" "details" "city" '"London"')
echo "Associated 'user.details.city': $nested_map_assoc"
echo

echo "--- dissoc_in ---"
nested_map_dissoc=$(dissoc_in "$nested_map_assoc" "user" "roles")
echo "Dissociated 'user.roles': $nested_map_dissoc"
echo

# merge, update, and update_in

# Merges two or more JSON objects together.
# Keys in later objects overwrite keys from earlier ones (shallow merge).
# Usage: merge '{"a": 1}' '{"b": 2, "a": 99}' '{"c": 3}'
merge() {
    if [ "$#" -lt 2 ]; then
        echo "Error: merge requires at least two JSON object arguments." >&2
        return 1
    fi
    # CORRECTED: Use printf to pipe each argument as a separate JSON text into jq.
    # The --slurp (-s) flag then reads this stream into an array,
    # and the 'add' filter merges all the objects in that array.
    printf '%s\n' "$@" | jq -s 'add'
}

# Updates a value in a map by applying a function to it.
# The "function" is a jq filter string.
# Usage: update '{"a": 10}' "a" '. + 5'
# Usage: update '{"names": ["a"]}' "names" '. + ["b"]'
update() {
    if [ "$#" -ne 3 ]; then
        echo "Error: update requires three arguments: a JSON object, a key, and a jq filter string." >&2
        return 1
    fi
    local json_obj="$1"
    local key="$2"
    local jq_filter="$3"

    # We must construct the jq program string dynamically
    local jq_program
    jq_program=$(printf '.["%s"] |= (%s)' "$key" "$jq_filter")

    echo "$json_obj" | jq "$jq_program"
}

# Updates a value in a nested structure by applying a function.
# The "function" is a jq filter string.
# The path is specified by one or more key arguments.
# Usage: update_in '{"user": {"score": 100}}' "user" "score" '. * 1.5'
update_in() {
    if [ "$#" -lt 4 ]; then
        echo "Error: update_in requires at least four arguments: a JSON object, one or more path keys, and a jq filter string." >&2
        return 1
    fi
    local json_obj="$1"
    shift
    local jq_filter="${@: -1}"  # The last argument is the filter
    local path_keys=("${@:1:$#-1}") # All arguments except the last

    local path_jq=""
    for key in "${path_keys[@]}"; do
        path_jq+=$(printf '["%s"]' "$key")
    done

    local jq_program=$(printf '.%s |= (%s)' "$path_jq" "$jq_filter")

    echo "$json_obj" | jq "$jq_program"
}


# --- Examples ---
echo "--- merge ---"
map1='{"name": "base", "version": 1}'
map2='{"status": "active", "version": 2}'
map3='{"enabled": true}'
merged_map=$(merge "$map1" "$map2" "$map3")
echo "Merged map: $merged_map"
echo

echo "--- update ---"
score_map='{"player": "Alex", "score": 100}'
updated_score_map=$(update "$score_map" "score" '. + 50')
echo "Updated score: $updated_score_map"
echo

echo "--- update (on an array) ---"
tags_map='{"post": 1, "tags": ["tech"]}'
updated_tags_map=$(update "$tags_map" "tags" '. + ["dev", "jq"]')
echo "Updated tags: $updated_tags_map"
echo

echo "--- update_in ---"
nested_data='{"user": {"stats": {"logins": 10, "last_login": "2023-10-27"}}}'
updated_nested_data=$(update_in "$nested_data" "user" "stats" "logins" '. + 1')
echo "Updated nested logins: $updated_nested_data"
echo
