# curlpilot/deps.bash
set -euo pipefail

SCRIPT_REGISTRY_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if ! declare -p SCRIPT_REGISTRY > /dev/null 2>&1; then
  declare -A SCRIPT_REGISTRY
fi

register_dep() {
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

  # Capture stdin and define paths
  local input
  input=$(cat)
  local base_path
  base_path="$(dirname "$script_path")/$(basename "$script_path" .bash)"
  local args_schema_path="${base_path}.args.schema.json"
  local input_schema_path="${base_path}.input.schema.json"
  local output_schema_path="${base_path}.output.schema.json"
  local validator_path="$SCRIPT_REGISTRY_DIR/schema_validator.bash"

  # --- Up-front Validator Check ---
  # If any schema file exists for this script, the validator MUST be present.
  if [[ -f "$args_schema_path" || -f "$input_schema_path" || -f "$output_schema_path" ]]; then
    if [[ ! -f "$validator_path" ]]; then
      echo "Error: A schema file was found, but the validator is missing or not executable at '$validator_path'." >&2
      return 1
    fi
  fi

  # --- Simplified ARGS Validation ---
  if [[ -f "$args_schema_path" ]]; then
    local args_json
    if [ "$#" -gt 0 ]; then
      args_json=$(printf '"%s",' "$@")
      args_json="[${args_json%,}]"
    else
      args_json="[]"
    fi
    local validation_errors
    validation_errors=$(echo "$args_json" | bash "$validator_path" "$args_schema_path" 2>&1)
    if [[ $? -ne 0 ]]; then
      echo "Error: Arguments for '$key' ($script_path) failed schema validation." >&2
      echo "Schema: $args_schema_path" >&2
      echo "--- Validation Errors ---" >&2
      echo "$validation_errors" >&2
      echo "--- Invalid Arguments (as JSON) ---" >&2
      echo "$args_json" >&2
      return 1
    fi
  fi

  # --- Simplified STDIN Validation ---
  if [[ -f "$input_schema_path" ]]; then
    local validation_errors
    validation_errors=$(echo "$input" | bash "$validator_path" "$input_schema_path" 2>&1)
    if [[ $? -ne 0 ]]; then
      echo "Error: Stdin for '$key' ($script_path) failed input schema validation." >&2
      echo "Schema: $input_schema_path" >&2
      echo "--- Validation Errors ---" >&2
      echo "$validation_errors" >&2
      echo "--- Invalid Input ---" >&2
      echo "$input" >&2
      return 1
    fi
  fi

  # --- Execute the script ---
  set +e
  local output
  output=$(echo "$input" | "$script_path" "$@")
  local exit_code=$?
  set -e

  # Handle script execution failure
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return $exit_code
  fi

  # --- Simplified OUTPUT Validation ---
  if [[ -f "$output_schema_path" ]]; then
    local validation_errors
    validation_errors=$(echo "$output" | bash "$validator_path" "$output_schema_path" 2>&1)
    if [[ $? -ne 0 ]]; then
      echo "Error: Output of '$key' ($script_path) failed output schema validation." >&2
      echo "Schema: $output_schema_path" >&2
      echo "--- Validation Errors ---" >&2
      echo "$validation_errors" >&2
      echo "--- Invalid Output ---" >&2
      echo "$output" >&2
      return 1
    fi
  fi

  # If everything passed, print the final output
  echo "$output"
}
get_script_registry() {
  declare -p SCRIPT_REGISTRY
}
