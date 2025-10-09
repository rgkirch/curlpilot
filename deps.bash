# curlpilot/deps.bash

# A sourced library file like deps.bash should never change the shell options of its caller. So, don't set -euox pipefail.

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/src/logging.bash"

# Set PROJECT_ROOT only if it is not already set. This makes the script
# testable and allows parent scripts to override the root directory.
: "${PROJECT_ROOT:="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"}"

# --- Tracing Initialization ---
# Initialize a root trace directory once per (test) run.
if [[ "${CURLPILOT_TRACE:-}" == "true" && -z "${CURLPILOT_TRACE_ROOT_DIR:-}" ]]; then
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    export CURLPILOT_TRACE_ROOT_DIR
    CURLPILOT_TRACE_ROOT_DIR="$(mktemp -d "${BATS_TEST_TMPDIR%/}/curlpilot-trace.${BATS_ROOT_PID:-$$}.XXXXXX")"
  else
    export CURLPILOT_TRACE_ROOT_DIR
    CURLPILOT_TRACE_ROOT_DIR="$(mktemp -d -t curlpilot-trace.XXXXXX)"
  fi
  log_info "CURLPILOT tracing enabled. Base log directory: ${CURLPILOT_TRACE_ROOT_DIR}"
fi
# Per-process base trace path (adds PID to avoid collisions)
if [[ -n "${CURLPILOT_TRACE_ROOT_DIR:-}" && -z "${CURLPILOT_TRACE_PATH:-}" ]]; then
  export CURLPILOT_TRACE_PATH="${CURLPILOT_TRACE_ROOT_DIR}/$(basename "$0" .bash).pid$$"
  mkdir -p "$CURLPILOT_TRACE_PATH"
fi
# --- End Tracing Initialization ---

_increment_counter() {
  local counter_file="$1"
  local child_num
  child_num=$(cat "$counter_file" 2>/dev/null || echo 0)
  child_num=$((child_num + 1))
  echo "$child_num" > "$counter_file"
  echo "$child_num"
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
  local final_path="$original_path"

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")
  if [[ -n "${!override_var_name-}" ]]; then
    final_path="${!override_var_name}"
  fi
  local new_resolved_path
  new_resolved_path=$(resolve_path "$final_path")

  if [[ -v SCRIPT_REGISTRY["$key"] ]]; then
    local existing_path="${SCRIPT_REGISTRY[$key]}"

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
      log_warn "Warning: Dependency '$key' was registered multiple times with the same path."
      return 0
    fi
  fi

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

  SCRIPT_REGISTRY["$key"]="$new_resolved_path"
}

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

exec_dep() {
  # --- Initial Checks ---
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

  # --- UNIFIED SETUP ---
  local trace_path=""
  local stdout_file stderr_file
  local exec_cmd exit_code
  local base_path="$(dirname "$script_path")/$(basename "$script_path" .bash)"
  local validator_path="$PROJECT_ROOT/src/schema_validator.bash"
  local stdout_schema_path="${base_path}.stdout.schema.json"
  local stderr_schema_path="${base_path}.stderr.schema.json"

  if [[ -n "${CURLPILOT_TRACE:-}" ]]; then
    # Setup for TRACING MODE (persistent files)
    trace_path="$CURLPILOT_TRACE_PATH/$(_increment_counter "$CURLPILOT_TRACE_PATH"/.counter)_$key"
    mkdir -p "$trace_path"
    stdout_file="${trace_path}/stdout"
    stderr_file="${trace_path}/stderr"
    exec_cmd=(env "CURLPILOT_TRACE_PATH=${trace_path}" bash "$script_path" "$@")

    # Write metadata
    jq -n --arg key "$key" --arg script_path "$script_path" \
      --arg cwd "$(pwd)" --arg pid "$$" --arg ppid "$PPID" \
      --arg timestamp "$(date -Iseconds)" \
      '{key:$key,script_path:$script_path,cwd:$cwd,pid:$pid,ppid:$ppid,timestamp:$timestamp}' \
      > "${trace_path}/meta.json"
    jq --null-input '$ARGS.positional' --args -- "$@" > "${trace_path}/args.json"
    log_debug "Executing dep '$key' with streaming trace to: $trace_path"
  else
    # Setup for NON-TRACING MODE (temporary files)
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    trap "rm -f '$stdout_file' '$stderr_file'" RETURN
    exec_cmd=(bash "$script_path" "$@")
  fi

  local stdout_pipe stderr_pipe
  stdout_pipe=$(mktemp -u); stderr_pipe=$(mktemp -u)
  mkfifo "$stdout_pipe" "$stderr_pipe"
  trap 'rm -f "$stdout_pipe" "$stderr_pipe"' EXIT

  tee "$stdout_file" < "$stdout_pipe" &
  tee "$stderr_file" < "$stderr_pipe" >&2 &

  set +e
  "${exec_cmd[@]}" >"$stdout_pipe" 2>"$stderr_pipe"
  exit_code=$?
  set -e
  wait # Wait for tee processes to finish

  if [[ -n "$trace_path" ]]; then
    echo "$exit_code" > "${trace_path}/exit_code"
  fi

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
}

get_script_registry() {
  declare -p SCRIPT_REGISTRY
}

mock_dep() {
  local original_path="src/$1"
  local mock_arg="$2"
  local mock_path

  # FIX: Handle both absolute and relative paths for the mock file.
  if [[ "$mock_arg" == /* ]]; then
    # It's an absolute path, use it directly.
    mock_path="$mock_arg"
  else
    # It's a relative path, assume it's inside test/.
    mock_path="test/$mock_arg"
  fi

  # We still check for the original file's existence to prevent typos.
  if [[ ! -f "$(resolve_path "$original_path")" ]]; then
    echo "Mocking ERROR: The original dependency file '$original_path' does not exist." >&2
    return 1
  fi

  local override_var_name
  override_var_name=$(_get_override_var_name "$original_path")

  export "$override_var_name"="$(resolve_path "$mock_path")"
}
