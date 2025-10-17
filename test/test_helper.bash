bats_require_minimum_version 1.5.0

setup() {
  source src/logging.bash
  if declare -f _setup > /dev/null; then
    _setup
  fi

  # --- TRACING SETUP (TEST CASE LEVEL) ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # Inherit the suite's path from setup_file
    local suite_path="${CURLPILOT_TRACE_PATH}"

    # Create a unique path for this specific test case.
    local test_case_path="${suite_path}/${BATS_TEST_NUMBER}"

    # CORRECT: Export this test case's path as the parent for _exec_dep calls
    export CURLPILOT_TRACE_PATH="$test_case_path"

    # Record this test case's start time.
    date +%s%N > "${CURLPILOT_TRACE_ROOT_DIR}/.test_start_time_ns_${BATS_TEST_NUMBER}"
  fi
}

teardown() {
  set -euo pipefail
  source src/logging.bash
  if declare -f _teardown > /dev/null; then
    _teardown
  fi

  # --- TRACING TEARDOWN (TEST CASE LEVEL) ---
  if [[ -f "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id" ]]; then
    log_debug "Teardown: Recording BATS test case data..."
    local suite_id start_time_ns end_time_ns
    suite_id=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id")
    start_time_ns=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.test_start_time_ns_${BATS_TEST_NUMBER}")
    end_time_ns=$(date +%s%N)

    # Re-create the paths
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
    local test_case_path="${suite_path}/${BATS_TEST_NUMBER}"
    local test_case_id="${test_case_path#$CURLPILOT_TRACE_ROOT_DIR/}"

    mkdir -p "$test_case_path"
    local record_file="${test_case_path}/record.ndjson"

    local test_exit_code=0
    [[ "${BATS_TEST_FAILED:-}" == "1" ]] && test_exit_code=1

    jq --null-input --compact-output \
      '{
        name: $name, id: $id, parentId: $parentId, pid: $pid,
        data: {
          start_timestamp_us: $ts, wall_duration_us: $dur,
          cpu_duration_us: null, max_rss_kb: null,
          major_page_faults: null, minor_page_faults: null,
          fs_inputs: null, fs_outputs: null,
          voluntary_context_switches: null,
          involuntary_context_switches: null,
          exit_code: $exit_code
        }
      }' \
      --arg name "$BATS_TEST_DESCRIPTION" \
      --arg id "$test_case_id" \
      --arg parentId "$suite_id" \
      --argjson pid "$$" \
      --argjson ts "$((start_time_ns / 1000))" \
      --argjson dur "$(((end_time_ns - start_time_ns) / 1000))" \
      --argjson exit_code "$test_exit_code" > "$record_file"

    # CORRECT: Reset the trace path back to the suite level for the next test.
    export CURLPILOT_TRACE_PATH="$suite_path"
  fi

  # If tracing is enabled and the test failed, dump artifact files for debugging.
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]] && [[ -n "${BATS_ERROR_STATUS:-}" && "${BATS_ERROR_STATUS}" -ne 0 ]] && [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
    echo "--- Teardown File Dump For Test: '$BATS_TEST_DESCRIPTION' ---" >&3
    find "$BATS_TEST_TMPDIR" -type f\
      -not -name 'record.ndjson' \
      -not -name .counter \
      -not -name .start_time_ns \
      -print0 | sort -z | xargs -0 head &> /dev/fd/3 || true
  fi
}

setup_file() {
  if declare -f _setup_file > /dev/null; then
    _setup_file
  fi

  # --- TRACING SETUP (SUITE LEVEL) ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # Use the BATS_FILE_TMPDIR variable, which is guaranteed to exist.
    export CURLPILOT_TRACE_ROOT_DIR="${BATS_FILE_TMPDIR}/curlpilot-trace"
    mkdir -p "$CURLPILOT_TRACE_ROOT_DIR"

    # Generate a clean, stable ID for this test file (the "suite").
    local suite_id="bats_$(basename "${BATS_TEST_FILENAME}" .bats)"

    # Store the suite ID and start time for other functions to use.
    echo "$suite_id" > "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id"
    date +%s%N > "${CURLPILOT_TRACE_ROOT_DIR}/.suite_start_time_ns"

    # CORRECT: Export the suite's path as the parent for setup()
    export CURLPILOT_TRACE_PATH="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
  fi
}

teardown_file() {
  if declare -f _teardown_file > /dev/null; then
    _teardown_file
  fi

  # --- TRACING TEARDOWN (SUITE LEVEL) ---
  if [[ -f "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id" ]]; then
    log_debug "Teardown: Recording BATS suite data..."
    local suite_id start_time_ns end_time_ns
    suite_id=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id")
    start_time_ns=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.suite_start_time_ns")
    end_time_ns=$(date +%s%N)

    # The root record is stored in its own directory.
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
    mkdir -p "$suite_path"
    local record_file="${suite_path}/record.ndjson"

    jq --null-input --compact-output \
      '{
        name: $name, id: $id, parentId: "", pid: $pid,
        data: {
          start_timestamp_us: $ts, wall_duration_us: $dur,
          cpu_duration_us: null, max_rss_kb: null,
          major_page_faults: null, minor_page_faults: null,
          fs_inputs: null, fs_outputs: null,
          voluntary_context_switches: null,
          involuntary_context_switches: null,
          exit_code: 0
        }
      }' \
      --arg name "$(basename "${BATS_TEST_FILENAME}")" \
      --arg id "$suite_id" \
      --argjson pid "$$" \
      --argjson ts "$((start_time_ns / 1000))" \
      --argjson dur "$(((end_time_ns - start_time_ns) / 1000))" > "$record_file"

    # Clean up temp files
    #rm -f "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id" \
    #      "${CURLPILOT_TRACE_ROOT_DIR}/.suite_start_time_ns"
    #find "$CURLPILOT_TRACE_ROOT_DIR" -name ".test_start_time_ns_*" -delete
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
