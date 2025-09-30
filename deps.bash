# curlpilot/deps.bash
#. ./libs/TickTick/ticktick.sh
#scripts intended to be sourced should not change the environment of the caller. so, don't set -euox pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/src/logging.bash"

# A sourced library file like deps.bash should never change the shell options of
# its caller. This is the root cause of all the strange behavior you've been
# seeing.

#export PS4='+\e[0;33m${BASH_SOURCE##*/}:${LINENO}\e[0m '

# The directory containing this script is now officially the PROJECT_ROOT.
PROJECT_ROOT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SCRIPT_REGISTRY_DIR="$PROJECT_ROOT"

if ! declare -p SCRIPT_REGISTRY > /dev/null 2>&1; then
  declare -A SCRIPT_REGISTRY
fi

get_project_root() {
  echo "$PROJECT_ROOT"
}

resolve_path() {
  local relative_path="$1"
  if [[ "$relative_path" = /* ]]; then
    echo "$relative_path"
  else
    echo "$PROJECT_ROOT/$relative_path"
  fi
}

path_relative_to_here() {
  local relative_path="$1"
  # BASH_SOURCE[1] is the path to the script that called this function (which sourced deps.bash).
  local caller_path="${BASH_SOURCE[1]}"
  if [[ -z "$caller_path" ]]; then
    # Fallback if not called from a sourced script (e.g. interactive shell)
    # In this case, it behaves like resolve_path
    resolve_path "$relative_path"
  else
    local caller_dir
    caller_dir=$(dirname "$(readlink -f "$caller_path")")
    if [[ "$relative_path" = /* ]]; then
      echo "$relative_path"
    else
      echo "$caller_dir/$relative_path"
    fi
  fi
}

# --- Internal Helper Function ---
# Derives the override environment variable name from a script's original path.
# @param1: The original path of the dependency (e.g., "copilot/auth.bash").
_get_override_var_name() {
  local original_path="$1"
  local relative_path="$original_path"

  # If the path is absolute and starts with the project root, convert it to relative.
  if [[ "$relative_path" == "$PROJECT_ROOT/"* ]]; then
    relative_path="${relative_path#$PROJECT_ROOT/}"
  fi

  local sanitized_path
  # The original logic is preserved to avoid collisions (e.g. 'foo/bar' vs 'foo_bar')
  sanitized_path=$(echo "$relative_path" | tr 'a-z' 'A-Z' | sed -e 's/\//__/g' -e 's/\./_/g' -e 's/[^a-zA-Z0-9_]/_/g')
  echo "CPO_$sanitized_path"
}

register_dep() {
  local key="$1"
  local original_path="src/$2"
  local final_path="$original_path"

  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    return 0
  fi

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  if [[ -n "${!override_var_name-}" ]]; then
    final_path="${!override_var_name}"
  fi

  local resolved_path
  resolved_path=$(resolve_path "$final_path")

  # Check if the final resolved file exists.
  if [[ ! -f "$resolved_path" ]]; then
    {
      echo "---"
      echo "ERROR: Dependency Registration Failed"
      echo "  in script: $0"
      echo
      echo "File not found for dependency key: '$key'"
      echo "Attempted to resolve path: '$resolved_path'"
      echo
      echo "Debugging Info:"
      echo "  - Original Path: '$original_path'"
      if [[ "$final_path" != "$original_path" ]]; then
        echo "  - Overridden by:   '$override_var_name'"
        echo "  - Override Value:  '$final_path'"
      else
        echo "  - No override was used."
      fi
      echo "---"
    } >&2
    exit 1
  fi

  SCRIPT_REGISTRY["$key"]="$resolved_path"
}

exec_dep() {
  if ! declare -p SCRIPT_REGISTRY >/dev/null 2>&1; then
    echo "Error (deps.bash): SCRIPT_REGISTRY is not defined." >&2
    echo "  This means the test environment was not set up in the 'run' subshell." >&2
    exit 1
  fi

  local key="$1"
  local script_path="${SCRIPT_REGISTRY[$key]}"

  if [[ -z "$script_path" ]]; then
    echo "Error: No script registered for key '$key'" >&2
    return 1
  fi
  if [[ ! -f "$script_path" ]]; then
    echo "Error: Script file '$script_path' does not exist." >&2
    return 1
  fi
  shift

  local base_path
  base_path="$(dirname "$script_path")/$(basename "$script_path" .bash)"
    local output_schema_path="${base_path}.output.schema.json"
  local validator_path="$PROJECT_ROOT/src/schema_validator.bash"

  if [[ -f "$output_schema_path" ]]; then
    if [[ ! -f "$validator_path" ]]; then
      echo "Error: A schema file was found, but the validator is missing or not executable at '$validator_path'." >&2
      return 1
    fi
  fi

  output_file=$(mktemp)
  trap 'rm -f "$output_file"' RETURN

  set +e
  bash "$script_path" "$@" > "$output_file"
  local exit_code=$?
  set -e

  if [[ $exit_code -ne 0 ]]; then
    cat "$output_file" >&2
    return $exit_code
  fi

  if [[ -f "$output_schema_path" ]]; then
    set +e
    local validation_errors
    validation_errors=$(cat "$output_file" | bash "$validator_path" "$output_schema_path" 2>&1)
    local validation_code=$?
    set -e
    if [[ $validation_code -ne 0 ]]; then
      echo "Error: Output of '$key' ($script_path) failed output schema validation." >&2
      echo "Schema: $output_schema_path" >&2
      echo "--- Validation Errors ---" >&2
      echo "$validation_errors" >&2
      echo "--- Invalid Output ---" >&2
      cat "$output_file" >&2
      return 1
    fi
  fi

  cat "$output_file"
}

get_script_registry() {
  declare -p SCRIPT_REGISTRY
}

# Sets a mock for a dependency script and validates the original path exists.
# This prevents tests from silently passing if a real dependency is moved or deleted.
#
# @param1 The original, real path to the dependency (e.g., "copilot/auth.bash").
# @param2 The path to the mock script to use instead.
mock_dep() {
  local original_path="src/$1"
  local mock_path="test/$2"

  # 1. Validate that the real dependency file actually exists.
  #    This is the key improvement that catches refactoring errors.
  if [[ ! -f "$(resolve_path "$original_path")" ]]; then
    echo "Mocking ERROR: The original dependency file '$original_path' does not exist." >&2
    return 1
  fi

  # 2. Derive the override variable name using the shared helper function.
  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  # 3. Export the variable with the resolved path to the mock.
  export "$override_var_name"="$(resolve_path "$mock_path")"
}
