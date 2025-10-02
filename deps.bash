# curlpilot/deps.bash
#. ./libs/TickTick/ticktick.sh

# A sourced library file like deps.bash should never change the shell options of its caller. So, don't set -euox pipefail.

#export PS4='+\e[0;33m${BASH_SOURCE##*/}:${LINENO}\e[0m '
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/src/logging.bash"

# The directory containing this script is now officially the PROJECT_ROOT.
PROJECT_ROOT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# --- Tracing Initialization ---
# If tracing is enabled via "true", create a base temporary directory.
if [[ "${CURLPILOT_TRACE_DIR:-}" == "true" ]]; then
  export CURLPILOT_TRACE_DIR
  CURLPILOT_TRACE_DIR="$(mktemp -d -t curlpilot-trace.XXXXXX)"
  echo "CURLPILOT tracing enabled. Base log directory: ${CURLPILOT_TRACE_DIR}" >&2
fi

# If tracing is enabled, ensure the environment is isolated for this process tree.
if [[ -n "${CURLPILOT_TRACE_DIR:-}" ]]; then
  # If CURLPILOT_TRACE_ROOT_PID is not set, this is the root of a new trace.
  if [[ -z "${CURLPILOT_TRACE_ROOT_PID:-}" ]]; then
    # Create an isolated subdirectory named after our own Process ID.
    local pid_dir="${CURLPILOT_TRACE_DIR}/$$"
    mkdir -p "$pid_dir"

    # Re-export the trace directory to point to our isolated subdirectory.
    export CURLPILOT_TRACE_DIR="$pid_dir"

    # Export our PID as the root for all children to see.
    export CURLPILOT_TRACE_ROOT_PID="$$"
  fi

  # Initialize trace IDs and names if they are not already set for this process.
  if [[ -z "${CURLPILOT_TRACE_ID:-}" ]]; then
    export CURLPILOT_TRACE_ID
    CURLPILOT_TRACE_ID=$(printf "%0${CURLPILOT_TRACE_PADDING:-0}d" "1")
  fi
  if [[ -z "${CURLPILOT_TRACE_NAME:-}" ]]; then
    export CURLPILOT_TRACE_NAME
    CURLPILOT_TRACE_NAME=$(basename "$0" .bash)
  fi
fi

# Counter for child processes spawned by exec_dep from the current context.
_CURLPILOT_EXEC_DEP_COUNTER=0
# --- End Tracing Initialization ---


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
  local caller_path="${BASH_SOURCE[1]}"
  if [[ -z "$caller_path" ]]; then
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

_get_override_var_name() {
  local original_path="$1"
  local relative_path="$original_path"

  if [[ "$relative_path" == "$PROJECT_ROOT/"* ]]; then
    relative_path="${relative_path#$PROJECT_ROOT/}"
  fi

  local sanitized_path
  sanitized_path=$(echo "$relative_path" | tr 'a-z' 'A-Z' | sed -e 's/\//__/g' -e 's/\./_/g' -e 's/[^a-zA-Z0-9_]/_/g')
  echo "CPO_$sanitized_path"
}

register_dep() {
  local key="$1"
  local original_path="src/$2"
  local final_path="$original_path"

  # First, determine what the final path for this registration attempt will be.
  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")
  if [[ -n "${!override_var_name-}" ]]; then
    final_path="${!override_var_name}"
  fi
  local new_resolved_path
  new_resolved_path=$(resolve_path "$final_path")

  # Now, check if this key has been registered before.
  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    local existing_path="${SCRIPT_REGISTRY[$key]}"

    # If the new path is different from the old one, it's a fatal error.
    if [[ "$new_resolved_path" != "$existing_path" ]]; then
      {
        echo "---"
        echo "ERROR: Dependency Conflict"
        echo "  The key '$key' is already registered with a different path."
        echo
        echo "  - Existing Path: '$existing_path'"
        echo "  - Conflicting Path: '$new_resolved_path'"
        echo "---"
      } >&2
      exit 1
    else
      # If it's the same path, it's a benign re-registration. Issue a warning.
      log "Warning: Dependency '$key' was registered multiple times with the same path."
      return 0
    fi
  fi

  # This is a new registration. Check if the file exists before adding it.
  if [[ ! -f "$new_resolved_path" ]]; then
    {
      echo "---"
      echo "ERROR: Dependency Registration Failed"
      echo "  File not found for dependency key: '$key'"
      echo "  Attempted to resolve path: '$new_resolved_path'"
      echo "---"
    } >&2
    exit 1
  fi

  # Add the new, validated dependency to the registry.
  SCRIPT_REGISTRY["$key"]="$new_resolved_path"
}

exec_dep() (
  #set -euox pipefail
  #export PS4="+[$$] \${BASH_SOURCE##*/}:\${LINENO} "
  if ! declare -p SCRIPT_REGISTRY >/dev/null 2>&1; then
    echo "Error (deps.bash): SCRIPT_REGISTRY is not defined." >&2
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

  local output_file
  local exec_cmd
  local child_trace_id=""
  exec_cmd=(bash "$script_path" "$@")

  if [[ -n "${CURLPILOT_TRACE_DIR:-}" ]]; then
    _CURLPILOT_EXEC_DEP_COUNTER=$((_CURLPILOT_EXEC_DEP_COUNTER + 1))

    local child_id_part
    child_id_part=$(printf "%0${CURLPILOT_TRACE_PADDING:-0}d" "$_CURLPILOT_EXEC_DEP_COUNTER")
    child_trace_id="${CURLPILOT_TRACE_ID}.${child_id_part}"

    local trace_base_name="${child_trace_id}.${key}"
    output_file="${CURLPILOT_TRACE_DIR}/${trace_base_name}.output"

    log "Executing dep '$key' with TRACE_ID=$child_trace_id"
    exec_cmd=(env "CURLPILOT_TRACE_ID=${child_trace_id}" "CURLPILOT_TRACE_NAME=${key}" "${exec_cmd[@]}")
  else
    output_file=$(mktemp)
    trap "rm -f '$output_file'" RETURN
  fi


  set +e
  "${exec_cmd[@]}" > "$output_file"
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
      if [[ -n "$child_trace_id" ]]; then
        local trace_base_name="${child_trace_id}.${key}"
        local error_file="${CURLPILOT_TRACE_DIR}/${trace_base_name}.validation_errors"
        echo "$validation_errors" > "$error_file"
        echo "Validation errors for '$key' saved to: $error_file" >&2
      fi

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
)

get_script_registry() {
  declare -p SCRIPT_REGISTRY
}

mock_dep() {
  local original_path="src/$1"
  local mock_path="test/$2"

  if [[ ! -f "$(resolve_path "$original_path")" ]]; then
    echo "Mocking ERROR: The original dependency file '$original_path' does not exist." >&2
    return 1
  fi

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  export "$override_var_name"="$(resolve_path "$mock_path")"
}
