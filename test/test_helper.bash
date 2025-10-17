bats_require_minimum_version 1.5.0

_increment_counter() {
  local counter_file="$1"
  local child_num
  child_num=$(cat "$counter_file" 2>/dev/null || echo 0)
  child_num=$((child_num + 1))
  echo "$child_num" > "$counter_file"
  printf "%02d\n" "$child_num"
}

setup() {
  source src/logging.bash
  if declare -f _setup > /dev/null; then
    _setup
  fi

  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # Inherit the suite's path from setup_file
    local suite_path="${CURLPILOT_TRACE_PATH}"

    # Create a unique path for this specific test case.
    local test_case_path="${suite_path}/${BATS_TEST_NUMBER}"
    mkdir -p "$test_case_path" # Create the test case's own directory

    # Record this test case's start time inside its directory.
    date +%s%N > "${test_case_path}/.test_start_time_ns"

    # Export this test case's path as the parent for _exec_dep calls
    export CURLPILOT_TRACE_PATH="$test_case_path"
  fi
}

teardown() {
  set -euo pipefail
  source src/logging.bash
  if declare -f _teardown > /dev/null; then
    _teardown
  fi

  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    log_debug "Teardown: Recording BATS test case data..."
    local suite_id start_time_ns end_time_ns
    suite_id=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id") # Read suite ID

    # Re-create paths
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
    local test_case_path="${suite_path}/${BATS_TEST_NUMBER}"
    local test_case_id="${test_case_path#$CURLPILOT_TRACE_ROOT_DIR/}"

    # Read start time from the test case's directory.
    start_time_ns=$(cat "${test_case_path}/.test_start_time_ns")
    end_time_ns=$(date +%s%N)

    local record_file="${test_case_path}/record.ndjson"

    if [[ "${BATS_ERROR_STATUS:-}" == "1" ]]; then
      _increment_counter "${CURLPILOT_TRACE_ROOT_DIR}/.failed_test_count"
    fi

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
      --argjson exit_code "$BATS_ERROR_STATUS" > "$record_file"
  fi

  if [[ -n "${BATS_ERROR_STATUS:-}" && "${BATS_ERROR_STATUS}" -ne 0 ]] && [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
      if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
      echo "=== Teardown Dump of CURLPILOT_TRACE_PATH $CURLPILOT_TRACE_PATH ===" >&3
      find "$CURLPILOT_TRACE_PATH" -type f \
        -not -name .counter \
        -not -name .start_time_ns \
        -print0 | sort -z | xargs -0 head -n 200 &> /dev/fd/3 || true
    fi

    echo "=== Teardown Dump of BATS_TEST_TMPDIR $BATS_TEST_TMPDIR ===" >&3
    find "$BATS_TEST_TMPDIR" -type f \
      -print0 | sort -z | xargs -0 head -n 200 &> /dev/fd/3 || true
  fi
}


setup_file() {
  if declare -f _setup_file > /dev/null; then
    _setup_file
  fi

  # --- TRACING SETUP (SUITE LEVEL) ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    # Use the BATS_FILE_TMPDIR variable.
    export CURLPILOT_TRACE_ROOT_DIR="${BATS_FILE_TMPDIR}/curlpilot-trace"
    mkdir -p "$CURLPILOT_TRACE_ROOT_DIR"

    # Generate a clean, stable ID for this test file (the "suite").
    local suite_id="bats_$(basename "${BATS_TEST_FILENAME}" .bats)"
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"
    mkdir -p "$suite_path" # Create the suite's own directory

    # Store the start time inside the suite's directory.
    echo "$suite_id" > "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id" # Keep ID ref in root for setup()
    date +%s%N > "${suite_path}/.suite_start_time_ns" # Store time inside suite dir

    # Export the suite's path as the parent for setup()
    export CURLPILOT_TRACE_PATH="$suite_path"
  fi
}

teardown_file() {
  if declare -f _teardown_file > /dev/null; then
    _teardown_file
  fi

  # --- TRACING TEARDOWN (SUITE LEVEL) ---
  if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
    log_debug "Teardown: Recording BATS suite data..."
    local suite_id start_time_ns end_time_ns
    suite_id=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.suite_id")
    local suite_path="${CURLPILOT_TRACE_ROOT_DIR}/${suite_id}"

    # Read start time from the suite's directory.
    start_time_ns=$(cat "${suite_path}/.suite_start_time_ns")
    end_time_ns=$(date +%s%N)

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
    fi

  #echo "CURLPILOT_TRACE $CURLPILOT_TRACE" >&3
  #echo "BATS_ERROR_STATUS $BATS_ERROR_STATUS" >&3
  #echo "CURLPILOT_FAILED_TEST_COUNT $(cat "${CURLPILOT_TRACE_ROOT_DIR}/.failed_test_count")" >&3
    local failed_test_count
    failed_test_count=$(cat "${CURLPILOT_TRACE_ROOT_DIR}/.failed_test_count" 2>/dev/null || echo 0)
    if [[ "${CURLPILOT_TRACE:-}" == "true" ]] && [[ -n "$failed_test_count" && "$failed_test_count" -ne 0 ]]; then
      if [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -le 1 ]]; then
        echo "=== File Teardown Dump of CURLPILOT_TRACE_ROOT_DIR $CURLPILOT_TRACE_ROOT_DIR ===" >&3
        find "$CURLPILOT_TRACE_ROOT_DIR" \
          -path "$CURLPILOT_TRACE_PATH/[0-9]*" -prune -o \
          -type f \
          -print0 | sort -z | xargs -0 head -n 200 &> /dev/fd/3 || true
      else
        echo "=== File Teardown Dump of CURLPILOT_TRACE_ROOT_DIR $CURLPILOT_TRACE_ROOT_DIR ===" >&3
        find "$CURLPILOT_TRACE_ROOT_DIR" \
          -type f \
          -print0 | sort -z | xargs -0 head -n 200 &> /dev/fd/3 || true
      fi
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
