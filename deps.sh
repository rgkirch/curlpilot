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

  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    return 0
  fi

  local sanitized_path
  sanitized_path=$(echo "$original_path" | tr 'a-z' 'A-Z' | sed -e 's/\//__/g' -e 's/\./_/g')
  local override_var_name="CPO_$sanitized_path"

  if [[ -n "${!override_var_name-}" ]]; then
    final_path="${!override_var_name}"
  fi

  if [[ "$final_path" = /* ]]; then
    SCRIPT_REGISTRY["$key"]="$final_path"
  else
    SCRIPT_REGISTRY["$key"]="$SCRIPT_REGISTRY_DIR/$final_path"
  fi
}

exec_dep() {
  local key="$1"
  local script_path="${SCRIPT_REGISTRY[$key]}"

  if [[ -z "$script_path" ]]; then
    echo "Error: No script registered for key '$key'" >&2
    return 1
  fi
  if [[ ! -x "$script_path" ]]; then
    echo "Error: Script file '$script_path' is not executable or does not exist." >&2
    return 1
  fi
  shift

  # Determine the potential path for the output schema based on convention.
  # e.g., for "config.sh", it looks for "config.output.schema.json"
  local schema_path
  schema_path="$(dirname "$script_path")/$(basename "$script_path" .sh).output.schema.json"

  # Temporarily disable exit-on-error to safely capture the exit code
  set +e
  local output
  output=$("$script_path" "$@")
  local exit_code=$?
  set -e

  # If the executed script failed, report its output as an error and propagate its exit code.
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return $exit_code
  fi

  # If a corresponding schema file exists, perform validation.
  if [[ -f "$schema_path" ]]; then
    local validator_path="$SCRIPT_REGISTRY_DIR/schema_validator.sh"

    if [[ ! -x "$validator_path" ]]; then
      echo "Warning: Schema validator not found at '$validator_path'. Skipping validation for '$key'." >&2
    else
      # Pipe the output to the validator and capture any validation errors
      local validation_errors
      validation_errors=$(echo "$output" | "$validator_path" "$schema_path" 2>&1)
      local validation_code=$?

      if [[ $validation_code -ne 0 ]]; then
        echo "Error: Output of '$key' ($script_path) failed schema validation." >&2
        echo "Schema: $schema_path" >&2
        echo "--- Validation Errors ---" >&2
        echo "$validation_errors" >&2
        echo "--- Invalid Output ---" >&2
        echo "$output" >&2
        return 1 # Return a generic error code for validation failure
      fi
    fi
  fi

  # If we reach here, the script succeeded and passed validation (or had no schema).
  # Print the original captured output to stdout for the caller to use.
  echo "$output"
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

  shift
  source "$path" "$@"
}

get_script_registry() {
  declare -p SCRIPT_REGISTRY
}
