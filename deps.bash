# curlpilot/deps.bash

# A sourced library file like deps.bash should never change the shell options of its caller. So, don't set -euox pipefail.

# Use a path relative to this script's location to find its own helpers.
# This decouples it from PROJECT_ROOT and makes it safe for sandboxed testing.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/src/logging.bash"

# Use conditional assignment. This allows a test suite to override PROJECT_ROOT.
: "${PROJECT_ROOT:="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"}"

_increment_counter() {
  local counter_file="$1"
  local child_num
  child_num=$(cat "$counter_file" 2>/dev/null || echo 0)
  child_num=$((child_num + 1))
  echo "$child_num" > "$counter_file"
  printf "%02d\n" "$child_num"
}


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

  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    local existing_path="${SCRIPT_REGISTRY[$key]}"
    if [[ "$original_path" != "$existing_path" ]]; then
      {
        echo "---"
        echo "ERROR: Dependency Conflict"
        echo "  The key '$key' is already registered with '$existing_path'."
        echo "  Attempted to re-register with '$original_path'."
        echo "---"
      } >&2
      exit 1
    else
      log_warn "Warning: Dependency '$key' was registered multiple times with the same path."
      return 0
    fi
  fi

  # Still check for the existence of the REAL file as a sanity check.
  local resolved_original_path
  resolved_original_path=$(resolve_path "$original_path")
  if [[ ! -f "$resolved_original_path" ]]; then
    {
      echo "---"
      echo "ERROR: Dependency Registration Failed"
      echo "  File not found for dependency key: '$key'"
      echo "  Attempted to resolve original path: '$resolved_original_path'"
      echo "---"
    } >&2
    exit 1
  fi

  # Store the canonical path in the registry.
  SCRIPT_REGISTRY["$key"]="$original_path"
}

# Helper function for validation
_validate_stream() {
  local stream_name="$1"
  local captured_file="$2"
  local schema_file="$3"
  local validator_path="$4"
  local key="$5"
  local trace_path="$6" # Can be empty

  if [[ ! -f "$schema_file" ]]; then
    return 0 # No schema, no validation needed.
  fi

  set +e
  local validation_errors
  validation_errors=$(cat "$captured_file" | bash "$validator_path" "$schema_file" 2>&1)
  local validation_code=$?
  set -e

  if [[ $validation_code -ne 0 ]]; then
    echo "Error: The '${stream_name}' of '$key' failed schema validation." >&2
    echo "Schema: $schema_file" >&2
    echo "--- Validation Errors ---" >&2
    echo "$validation_errors" >&2
    echo "--- Invalid Output (${stream_name}) ---" >&2
    cat "$captured_file" >&2
    if [[ -n "$trace_path" ]]; then
        echo "$validation_errors" > "${trace_path}/${stream_name}_validation_errors"
    fi
    return 1
  fi
  return 0
}

# The public-facing function for executing a registered dependency.
exec_dep() {
  if ! declare -p SCRIPT_REGISTRY >/dev/null 2>&1; then
    log_error "SCRIPT_REGISTRY is not defined."
    exit 1
  fi
  local key="$1"
  shift

  # REFACTORED: This is where the mock is resolved (late binding).
  local original_path="${SCRIPT_REGISTRY[$key]}"
  if [[ -z "$original_path" ]]; then
    log_error "No script registered for key '$key'"
    return 1
  fi

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  local final_path
  if [[ -n "${!override_var_name-}" ]]; then
    # A mock is defined, use its path.
    final_path="${!override_var_name}"
  else
    # No mock, use the original path from the registry.
    final_path="$original_path"
  fi

  # Resolve the chosen path to an absolute path for execution.
  local resolved_path
  resolved_path=$(resolve_path "$final_path")

  # Call the internal execution function with the final, resolved path.
  _exec_dep "$resolved_path" "$key" "$@"
}

_exec_dep() (
  set -euo pipefail
  # --- Initial Checks ---
  local script_path="$1"
  local key="$2"
  if [[ ! -f "$script_path" ]]; then
    log_error "Script file '$script_path' does not exist."
    return 1
  fi
  shift 2

  local trace_path=""
  local stdout_file stderr_file
  local exec_cmd exit_code
  local base_path="$(dirname "$script_path")/$(basename "$script_path" .bash)"
  local validator_path="$PROJECT_ROOT/src/schema_validator.bash"
  local stdout_schema_path="${base_path}.stdout.schema.json"
  local stderr_schema_path="${base_path}.stderr.schema.json"

  # --- Tracing Path Setup ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # If a root is already defined (by BATS or a parent process), use it.
    # Otherwise, create one for this new standalone trace.
    local trace_root="${CURLPILOT_TRACE_ROOT_DIR:-$(mktemp -d -t curlpilot-trace.XXXXXX)}"

    # If this is the first call in a standalone trace, export the new root so children can find it.
    if [[ -z "${CURLPILOT_TRACE_ROOT_DIR:-}" ]]; then
        export CURLPILOT_TRACE_ROOT_DIR="$trace_root"
    fi

    # If a parent process has set a path, create a subdirectory within it.
    # Otherwise, create a new top-level directory within the root.
    local parent_path="${CURLPILOT_TRACE_PATH:-$trace_root}"
    trace_path="${parent_path}/$(_increment_counter "${parent_path}"/.counter)_$key"
    mkdir -p "$trace_path"
    stdout_file="${trace_path}/stdout"
    stderr_file="${trace_path}/stderr"

    # Pass the ROOT dir to all children.
    # Pass the NEW, more specific PATH to our direct children.
    exec_cmd=(env "CURLPILOT_TRACE_ROOT_DIR=${trace_root}" "CURLPILOT_TRACE_PATH=${trace_path}" bash "$script_path" "$@")
  else
    # NON-TRACING MODE
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    trap "rm -f '$stdout_file' '$stderr_file'" RETURN
    exec_cmd=(bash "$script_path" "$@")
  fi

  # --- Execution and I/O Redirection ---
  local stdout_pipe stderr_pipe
  stdout_pipe=$(mktemp -u); stderr_pipe=$(mktemp -u)
  mkfifo "$stdout_pipe" "$stderr_pipe"
  trap 'rm -f "$stdout_pipe" "$stderr_pipe"' EXIT
  tee -ap "$stdout_file" < "$stdout_pipe" &
  tee -ap "$stderr_file" < "$stderr_pipe" >&2 &

  # --- Timing and Execution ---
  local start_time_ns
  start_time_ns=$(date +%s%N)
  set +e
  "${exec_cmd[@]}" >"$stdout_pipe" 2>"$stderr_pipe"
  exit_code=$?
  set -e
  wait
  local end_time_ns duration_ns
  end_time_ns=$(date +%s%N)
  duration_ns=$((end_time_ns - start_time_ns))

  # --- Tracing Finalization Logic ---
  if [[ -n "$trace_path" ]]; then
    local start_time_us=$((start_time_ns / 1000))
    local duration_us=$((duration_ns / 1000))
    local self_event_log="${trace_path}/events.log"

    # Step 1: Write THIS process's own event to its raw event log.
    jq -n --compact-output \
      --arg name "$key" --arg cat "deps" --arg ph "X" \
      --argjson ts "$start_time_us" --argjson dur "$duration_us" \
      --argjson pid "$$" --argjson tid "$$" \
      --args -- "$@" \
      '{name:$name, cat:$cat, ph:$ph, ts:$ts, dur:$dur, pid:$pid, tid:$tid, args:{argv: $ARGS.positional}}' > "$self_event_log"

    # Step 2: Gather the raw event logs from DIRECT CHILDREN ONLY and append them.
    find "$trace_path" -mindepth 2 -maxdepth 2 -name "events.log" -print0 | \
      xargs -0 --no-run-if-empty cat >> "$self_event_log"

    # Step 3: ALWAYS create the final, user-facing trace.json for this level.
    local final_trace_file="${trace_path}/trace.json"
    jq -s '{traceEvents: .}' < "$self_event_log" > "$final_trace_file"

    echo "$exit_code" > "${trace_path}/exit_code"
  fi

  # --- Schema Validation ---
  if [[ $exit_code -ne 0 ]]; then
    log_error "Dependency '$key' exited with code $exit_code (trace: ${trace_path:-N/A})"
    return $exit_code
  fi
  local all_validations_passed=true
  if ! _validate_stream "stdout" "$stdout_file" "$stdout_schema_path" "$validator_path" "$key" "$trace_path"; then
    all_validations_passed=false
  fi
  if ! _validate_stream "stderr" "$stderr_file" "$stderr_schema_path" "$validator_path" "$key" "$trace_path"; then
    all_validations_passed=false
  fi
  if ! $all_validations_passed; then
    return 1
  fi
  return 0
)

get_script_registry() {
  declare -p SCRIPT_REGISTRY
}

mock_dep() {
  local original_arg="$1"
  local mock_arg="$2"
  local original_path
  local mock_path

  # Handle absolute vs relative path for the ORIGINAL file
  if [[ "$original_arg" = /* ]]; then
    original_path="$original_arg"
  else
    original_path="src/$original_arg"
  fi

  # Handle absolute vs relative path for the MOCK file
  if [[ "$mock_arg" = /* ]]; then
    mock_path="$mock_arg"
  else
    mock_path="test/$mock_arg"
  fi

  if [[ ! -f "$(resolve_path "$original_path")" ]]; then
    echo "Mocking ERROR: The original dependency file does not exist at resolved path: '$(resolve_path "$original_path")'" >&2
    return 1
  fi

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  export "$override_var_name"="$(resolve_path "$mock_path")"
}
