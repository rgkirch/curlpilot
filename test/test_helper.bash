bats_require_minimum_version 1.5.0


setup() {
  source src/logging.bash
  if declare -f _setup > /dev/null; then
    _setup
  fi

  # --- TRACING SETUP (BATS MODE) ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # Establish the single root directory for all traces within this BATS test.
    export CURLPILOT_TRACE_ROOT_DIR="${BATS_TEST_TMPDIR}/curlpilot-trace"
    mkdir -p "$CURLPILOT_TRACE_ROOT_DIR"

    # Record the test's start time for use in teardown.
    date +%s%N > "${CURLPILOT_TRACE_ROOT_DIR}/.start_time_ns"
  fi
}

teardown() (
  set -euo pipefail
  source src/logging.bash
  if declare -f _teardown > /dev/null; then
    _teardown
  fi

  # --- TRACING TEARDOWN & FINALIZATION (BATS MODE) ---
  if [[ -f "${CURLPILOT_TRACE_ROOT_DIR}/.start_time_ns" ]]; then
    log_debug "Teardown: Finalizing BATS trace..."
    log_debug "Teardown: CURLPILOT_TRACE_ROOT_DIR is '${CURLPILOT_TRACE_ROOT_DIR}'"

    local start_time_ns end_time_ns duration_ns
    start_time_ns=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.start_time_ns")
    end_time_ns=$(date +%s%N)
    duration_ns=$((end_time_ns - start_time_ns))

    local start_time_us=$((start_time_ns / 1000))
    local duration_us=$((duration_ns / 1000))

    local root_event
    root_event=$(jq -n --compact-output \
      --arg name "$BATS_TEST_DESCRIPTION" --arg cat "test" --arg ph "X" \
      --argjson ts "$start_time_us" --argjson dur "$duration_us" \
      --argjson pid "$BATS_PID" --argjson tid "$BATS_PID" --argjson args "{}" \
      '{name:$name, cat:$cat, ph:$ph, ts:$ts, dur:$dur, pid:$pid, tid:$tid, args:$args}')

    local final_trace_file="${BATS_TEST_TMPDIR}/trace.json"
    log_debug "Teardown: Final trace file will be at '${final_trace_file}'"

    # --- Start of Debugging Logic ---
    local find_cmd=(find "$CURLPILOT_TRACE_ROOT_DIR" -mindepth 3 -maxdepth 3 -name "events.log" -print0)
    log_debug "Teardown: Running find command: ${find_cmd[*]}"

    # Capture the output of find to see if it's working
    local found_logs
    mapfile -d '' found_logs < <("${find_cmd[@]}")

    if (( ${#found_logs[@]} > 0 )); then
        log_debug "Teardown: Found ${#found_logs[@]} event logs to process:"
        printf "  - %s\n" "${found_logs[@]}" | while IFS= read -r line; do log_debug "$line"; done
    else
        log_debug "Teardown: WARNING - 'find' command did not locate any event.log files."
        log_debug "Teardown: Dumping directory structure of '${CURLPILOT_TRACE_ROOT_DIR}' for inspection:"
        tree "$CURLPILOT_TRACE_ROOT_DIR" 2>&1 | while IFS= read -r line; do log_debug "  | $line"; done || log_debug "  (tree command not found)"
    fi
    # --- End of Debugging Logic ---

    (
      echo "$root_event"
      if (( ${#found_logs[@]} > 0 )); then
          printf "%s\0" "${found_logs[@]}" | xargs -0 --no-run-if-empty cat
      fi
    ) | jq -s '{traceEvents: .}' > "$final_trace_file"
    log_debug "Teardown: Final trace file created."

    unset CURLPILOT_TRACE_ROOT_DIR
  fi

  # If tracing is enabled and the test failed, dump all files created during the test for debugging.
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]] && [[ -n "${BATS_ERROR_STATUS:-}" && "${BATS_ERROR_STATUS}" -ne 0 ]] && [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
    echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
    find "$BATS_TEST_TMPDIR" -type f -not -name trace.json -not -name events.log -print0 | sort -z | xargs -0 head &> /dev/fd/3 || true
  fi
)

setup_file() {
  if declare -f _setup_file > /dev/null; then
    _setup_file
  fi
}

teardown_file() {
  if declare -f _teardown_file > /dev/null; then
    _teardown_file
  fi
}


# --- LOAD BATS LIBRARIES ---

# First, calculate the absolute path to the project root relative to THIS script's location.
# This is the most reliable way to find the BATS helper libraries.
_BATS_LIBS_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the BATS helper libraries using this reliable, internal path.
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-support/load.bash"
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-assert/load.bash"
source "${_BATS_LIBS_PROJECT_ROOT}/libs/bats-file/load.bash"

# Now, set a default for the PROJECT_ROOT that tests will use.
# This allows an external script to override the value for sandboxing or other purposes,
# without breaking the library loading above.
: "${PROJECT_ROOT:=$_BATS_LIBS_PROJECT_ROOT}"
export PROJECT_ROOT


# --- CUSTOM ASSERTIONS & HELPERS ---

# Asserts that two JSON strings are semantically equal by sorting their keys.
assert_json_equal() {
  local actual="$1"
  local expected="$2"
  local sorted_actual
  local sorted_expected

  # The `|| true` prevents the command from failing the script if jq encounters
  # invalid JSON, allowing the final comparison to correctly report the failure.
  sorted_expected=$(echo "$expected" | jq -S . 2>/dev/null || true)
  sorted_actual=$(echo "$actual" | jq -S . 2>/dev/null || true)

  if [ "$sorted_actual" != "$sorted_expected" ]; then
    echo "FAIL: JSON output does not match expected." >&3
    echo "Expected:" >&3
    echo "$sorted_expected" >&3
    echo "Got:" >&3
    echo "$sorted_actual" >&3
    return 1
  fi
}
