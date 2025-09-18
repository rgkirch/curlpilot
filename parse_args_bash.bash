#!/usr/bin/env bash
set -euo pipefail

#
# A schema-driven argument parser that converts a JSON array of arguments
# into a final JSON object based on a provided specification. This script
# uses a functional, pipeline-based approach with an emphasis on debuggability.
#
# Usage:
#   ./parse_args.bash '{"spec": {...}, "args": ["--foo", "bar"]}'
#

## --- Helper Functions ---

# Aborts with a formatted error message.
abort() {
  echo "Error: $1" >&2
  exit 1
}

# (Step 2) Removes metadata keys (starting with "_") from a spec JSON.
_clean_spec() {
  jq 'with_entries(select(.key | startswith("_") | not))'
}

# (Step 4) Validates that default values in the spec match their declared types.
_validate_spec_defaults() {
  local spec_json="$1"
  local keys_to_check
  keys_to_check=$(jq -r '[. | to_entries[] | select(.value.default != null) | .key] | .[]' <<< "$spec_json")

  for key in $keys_to_check; do
    local spec_entry
    spec_entry=$(jq --arg k "$key" '.[$k]' <<< "$spec_json")
    local expected_type
    expected_type=$(jq -r '.type' <<< "$spec_entry")
    local default_value
    default_value=$(jq '.default' <<< "$spec_entry")
    local actual_type
    actual_type=$(jq -r 'if type == "object" or type == "array" then "json" else type end' <<< "$default_value")

    if [[ "$expected_type" != "$actual_type" ]]; then
      abort "Spec Error: Default for \"--${key}\" must be of type ${expected_type}, but got a value of type ${actual_type}."
    fi
  done
}

# (Step 5) Normalizes ONLY boolean flags (e.g., "--foo" -> "--foo=true").
_normalize_boolean_flags() {
  local spec_json="$1"
  local raw_args_json="$2"
  local boolean_keys_json
  boolean_keys_json=$(jq '[. | to_entries[] | select(.value.type == "boolean") | .key]' <<< "$spec_json")

  jq --argjson booleans "$boolean_keys_json" '
    map(
      . as $arg |
      if $arg | startswith("--") and (contains("=") | not) then
        ($arg | ltrimstr("--") | gsub("-"; "_")) as $key |
        if $booleans | index($key) then "\($arg)=true" else $arg end
      else
        $arg
      end
    )
  ' <<< "$raw_args_json"
}

# (Step 6) Splits all arguments into a flat list: ["key", "value", ...].
_split_key_value_pairs() {
  local normalized_args_json="$1"
  local -a arg_list
  mapfile -t arg_list < <(jq -r '.[]' <<< "$normalized_args_json")

  local -a flat_list
  local i=0
  while [[ $i -lt ${#arg_list[@]} ]]; do
    local arg="${arg_list[i]}"

    if ! [[ "$arg" == --* ]]; then
      abort "Invalid argument format: '$arg'. All arguments must be flags."
    fi

    local key
    local value
    if [[ "$arg" == *=* ]]; then
      key="${arg#--}"
      key="${key%%=*}"
      value="${arg#*=}"
      i=$((i + 1))
    else
      key="${arg#--}"
      if (( i + 1 >= ${#arg_list[@]} )) || [[ "${arg_list[i+1]}" == --* ]]; then
        abort "Argument '--$key' requires a value."
      fi
      value="${arg_list[i+1]}"
      i=$((i + 2))
    fi
    flat_list+=("$(sed 's/-/_/g' <<< "$key")")
    flat_list+=("$value")
  done
  jq -cn --args "${flat_list[@]}" '$ARGS.positional'
}

# (Step 7) Generates help text and exits.
_generate_help_text() {
  local description="$1"
  local spec_json="$2"
  local options_text
  options_text=$(jq --raw-output 'keys[] as $key | "  --\(($key | gsub("_"; "-")))\t\(.[$key].description // "")"' <<< "$spec_json")
  local help_message
  help_message=$(printf "%s\n\nUsage: [options]\n\nOptions:\n%s\n  --help\tShow this help message and exit." \
    "$description" \
    "$options_text"
  )
  jq --null-input --arg msg "$help_message" '{help: $msg}'
  exit 0
}

# (Step 8) Checks for duplicate keys in the flat list.
_check_for_duplicates() {
  local flat_list_json="$1"
  declare -A seen_keys
  local -a keys
  mapfile -t keys < <(jq -r '.[ range(0; length; 2) ]' <<< "$flat_list_json")

  for key in "${keys[@]}"; do
    if [[ -n "${seen_keys[$key]-}" ]]; then
      abort "Duplicate argument provided: --$key"
    fi
    seen_keys[$key]=1
  done
}

# (Step 9) Reads from stdin if a single "-" value is present.
_handle_stdin() {
  local flat_list_json="$1"
  local dash_count
  dash_count=$(jq '[.[] | select(. == "-")] | length' <<< "$flat_list_json")

  if [[ "$dash_count" -gt 1 ]]; then
    abort "Cannot read from stdin for more than one argument."
  elif [[ "$dash_count" -eq 1 ]]; then
    local stdin_content
    stdin_content=$(cat)
    jq --arg content "$stdin_content" 'map(if . == "-" then $content else . end)' <<< "$flat_list_json"
  else
    echo "$flat_list_json"
  fi
}

# (Step 10) Merges user values into the spec object and checks for unknown arguments.
_build_structured_object() {
  local spec_json="$1"
  local flat_list_json="$2"
  local result_json="$spec_json" # Start with the spec as the base

  local -a flat_list
  mapfile -t flat_list < <(jq -r '.[]' <<< "$flat_list_json")

  for (( i=0; i<${#flat_list[@]}; i+=2 )); do
    local key="${flat_list[i]}"
    local value="${flat_list[i+1]}"

    if ! jq -e --arg k "$key" 'has($k)' <<< "$result_json" > /dev/null; then
      abort "Unknown option '--$(sed 's/_/-/g' <<< "$key")'."
    fi
    # Merge the user's value into the spec entry for this key
    result_json=$(jq --arg k "$key" --arg v "$value" '.[$k].value = $v' <<< "$result_json")
  done
  echo "$result_json"
}

# (Step 11) Applies default values to entries that don't have a value yet.
_apply_defaults() {
  local object_with_user_values="$1"
  jq '
    with_entries(
      if (.value | has("value") | not) and (.value | has("default")) then
        .value.value = .value.default
      else
        .
      end
    )
  ' <<< "$object_with_user_values"
}

# (Step 12) Coerces types and validates that values match their declared types in the spec.
_validate_and_coerce_types() {
  local spec_with_values="$1"
  local result_json="$spec_with_values"
  local keys
  keys=$(jq -r 'keys[] | select(.[.] | has("value"))' <<< "$spec_with_values")

  for key in $keys; do
    local spec_entry
    spec_entry=$(jq --arg k "$key" '.[$k]' <<< "$result_json")
    local expected_type
    expected_type=$(jq -r '.type' <<< "$spec_entry")
    local value
    value=$(jq '.value' <<< "$spec_entry")

    # Coerce non-string types
    if [[ "$expected_type" != "string" ]] && [[ "$expected_type" != "path" ]]; then
      # Here strings pass the raw string, so fromjson is needed to interpret it
      value=$(jq 'try fromjson catch .' <<< "$value")
      result_json=$(jq --arg k "$key" --argjson v "$value" '.[$k].value = $v' <<< "$result_json")
    fi

    # Validate type
    local actual_type
    actual_type=$(jq -r 'if type == "object" or type == "array" then "json" else type end' <<< "$value")

    if [[ "$expected_type" != "$actual_type" ]]; then
      abort "Type Error: For \"--${key}\", expected ${expected_type} but got value \`$(jq -c . <<< "$value")\` (${actual_type})."
    fi
  done
  echo "$result_json"
}


# (Step 13) Checks for missing required arguments.
_check_required_args() {
  local final_spec_obj="$1"
  local required_keys
  required_keys=$(jq -r '[. | to_entries[] | select(.value.required == true) | .key] | .[]' <<< "$final_spec_obj")

  for key in $required_keys; do
    if ! jq -e --arg k "$key" '.[$k] | has("value")' <<< "$final_spec_obj" > /dev/null; then
      abort "Required argument missing: --$(sed 's/_/-/g' <<< "$key")"
    fi
  done
}

# Flattens the final rich spec object into a simple {key: value} object for output.
_flatten_final_object() {
  jq 'with_entries(select(.value | has("value"))) | with_entries(.value = .value.value)'
}

## --- Main Script ---
main() {
  if [[ -z "${1-}" ]]; then
      abort "Usage: $0 JOB_TICKET_JSON"
  fi
  local job_ticket_json="$1"

  # --- Setup and Spec Validation ---
  readonly HELP_SPEC_JSON='{"help": {"type": "boolean", "description": "Show this help message and exit."}}'
  local user_spec_json
  user_spec_json=$(jq '.spec // {}' <<< "$job_ticket_json")

  # 1. Capture Metadata
  local script_description
  script_description=$(jq -r '._description // ""' <<< "$user_spec_json")

  # 2. & 3. Clean Spec and Add Help
  local arg_spec_json
  arg_spec_json=$(jq -s '.[0] + .[1]' <<< "$HELP_SPEC_JSON"$'\n'"$user_spec_json")
  local clean_spec_json
  clean_spec_json=$(_clean_spec <<< "$arg_spec_json")

  # 4. Validate Spec Defaults
  _validate_spec_defaults "$clean_spec_json"

  # --- Argument Processing Pipeline ---
  local raw_args_json
  raw_args_json=$(jq '.args // []' <<< "$job_ticket_json")

  # 5. Normalize Boolean Flags
  local normalized_args_json
  normalized_args_json=$(_normalize_boolean_flags "$clean_spec_json" "$raw_args_json")

  # 6. Split into Key-Value Pairs
  local flat_key_value_list_json
  flat_key_value_list_json=$(_split_key_value_pairs "$normalized_args_json")

  # 7. Handle Help Request
  if jq -e '.[] | select(. == "help")' <<< "$flat_key_value_list_json" > /dev/null; then
    _generate_help_text "$script_description" "$clean_spec_json"
  fi

  # 8. Check for Duplicates
  _check_for_duplicates "$flat_key_value_list_json"

  # 9. Handle Stdin
  local list_with_stdin_json
  list_with_stdin_json=$(_handle_stdin <<< "$flat_key_value_list_json")

  # 10. Build Structured Object (also checks for unknown args)
  local spec_with_user_values
  spec_with_user_values=$(_build_structured_object "$clean_spec_json" "$list_with_stdin_json")

  # 11. Apply Defaults
  local spec_with_defaults
  spec_with_defaults=$(_apply_defaults "$spec_with_user_values")

  # 12. Validate and Coerce Types
  local final_spec_obj
  final_spec_obj=$(_validate_and_coerce_types "$spec_with_defaults")

  # 13. Check for Required Arguments
  _check_required_args "$final_spec_obj"

  # --- Final Output ---
  _flatten_final_object <<< "$final_spec_obj"
}

main "$@"
