#!/bin/bash

set -euo pipefail

# curlpilot/deps.sh

SCRIPT_REGISTRY_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if ! declare -p SCRIPT_REGISTRY > /dev/null 2>&1; then
  declare -A SCRIPT_REGISTRY
fi

register() {
  local key="$1"
  local original_path="$2"
  local final_path="$original_path"

  # If the key already exists in the registry, do nothing.
  # This gives mocks priority.
  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    return 0
  fi

  # Sanitize the path to create the override variable name.
  # Uppercase, convert / to __, and . to _
  local sanitized_path=$(echo "$original_path" | tr 'a-z' 'A-Z' | sed -e 's/\//__/g' -e 's/\./_/g')
  local override_var_name="CPO_$sanitized_path"

  # Check if the override environment variable is set and not empty
  # using indirect expansion.
  if [[ -n "${!override_var_name-}" ]]; then
    final_path="${!override_var_name}"
  fi

  # Register the final path (either original or override)
  if [[ "$final_path" = /* ]]; then
    SCRIPT_REGISTRY["$key"]="$final_path"
  else
    SCRIPT_REGISTRY["$key"]="$SCRIPT_REGISTRY_DIR/$final_path"
  fi
}

exec_dep() {
  local key="$1"
  local path="${SCRIPT_REGISTRY[$key]}"
  if [[ -z "$path" ]]; then
    echo "Error: No script registered for key '$key'" >&2
    return 1
  fi
  if [[ ! -x "$path" ]]; then
    echo "Error: Script file '$path' is not executable or does not exist." >&2
    return 1
  fi
  shift
  "$path" "$@"
}

source_dep() {
  local key="$1"
  local path="${SCRIPT_REGISTRY[$key]}"

  if [[ -z "$path" ]]; then
    echo "Error: No script registered for key '$key'" >&2
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "Error: Script file '$path' does not exist." >&2
    return 1
  fi

  # 1. Remove the 'key' argument from the list of positional parameters.
  shift

  # 2. Source the script, passing along all the *remaining* arguments.
  #    "$@" expands to all remaining positional parameters, properly quoted.
  source "$path" "$@"
}

get_script_registry() {
  # This function provides a clean way to export the entire
  # dependency map without exposing the internal variable name.
  declare -p SCRIPT_REGISTRY
}
