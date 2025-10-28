#!/bin/bash
#run_tests.bash
set -euo pipefail

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define and export a stable path to the BATS libraries.
export BATS_LIBS_DIR="$SCRIPT_DIR/libs"
BATS_EXECUTABLE="$BATS_LIBS_DIR/bats/bin/bats"

# Initialize variables.
export CURLPILOT_LOG_LEVEL="${CURLPILOT_LOG_LEVEL:-ERROR}"
export CURLPILOT_LOG_LEVEL_BATS="${CURLPILOT_LOG_LEVEL_BATS:-ERROR}"
export BATS_NUMBER_OF_PARALLEL_JOBS=1
BATS_ARGS=()
STRACE_CMD=()
SESSION_TMPDIR=""

# Set a default memory limit (in KiB). 8 GiB = 8 * 1024 * 1024 = 8388608 KiB
# This can be overridden by the environment variable or the --memory-limit flag.
DEFAULT_MEM_LIMIT_KB=$((8 * 1024 * 1024))
MEMORY_LIMIT_KB="${CURLPILOT_MEM_LIMIT_KB:-$DEFAULT_MEM_LIMIT_KB}"

# --- Phase 1: Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -j|--jobs)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: Flag '$1' requires an argument." >&2
        exit 1
      fi
      export BATS_NUMBER_OF_PARALLEL_JOBS="$2"
      BATS_ARGS+=("$1" "$2")
      shift 2
      ;;
    --verbose)
      export CURLPILOT_LOG_LEVEL_BATS=INFO
      echo "Log level set to INFO" >&2
      BATS_ARGS+=(--verbose-run)
      shift
      ;;
    --trace)
      export CURLPILOT_TRACE=true
      BATS_ARGS+=(--no-tempdir-cleanup)
      shift
      ;;
    --tempdir)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: Flag '$1' requires an argument." >&2
        exit 1
      fi
      SESSION_TMPDIR="$2"
      shift 2
      ;;
    --memory-limit)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: Flag '$1' requires an argument." >&2
        exit 1
      fi
      MEMORY_LIMIT_KB="$2"
      echo "Memory limit set to ${MEMORY_LIMIT_KB} KiB" >&2
      shift 2
      ;;
    *)
      BATS_ARGS+=("$1")
      shift
      ;;
  esac
done

# --- Phase 2: Setup Environment based on Parsed Arguments ---

# Finalize the top-level session temp directory.
: "${SESSION_TMPDIR:=$(mktemp -d)}"
echo "Session directory: $SESSION_TMPDIR" >&2

# Define the path for the BATS temp directory *inside* our session directory.
# We DO NOT create this; we pass the path to `bats` and let it create it.
BATS_RUN_TMPDIR="${SESSION_TMPDIR}/bats-run"

# If tracing is enabled, set up all log directories and arm the profiler.
if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
  echo "Tracing enabled (BASH_ENV and strace)." >&2

  export PROFILE_LOG_DIR="${SESSION_TMPDIR}/profile-logs"
  STRACE_LOG_DIR="${SESSION_TMPDIR}/strace-logs"
  mkdir -p "$PROFILE_LOG_DIR"
  mkdir -p "$STRACE_LOG_DIR"

  # Now, source the profiler. It will see and adopt our PROFILE_LOG_DIR.
  source ./src/profiling/profile.bash

  echo "BASH_ENV logs will be in: $PROFILE_LOG_DIR" >&2
  echo "strace logs will be in: $STRACE_LOG_DIR" >&2

  STRACE_CMD=(strace \
    --follow-forks --output-separately \
    --output="$STRACE_LOG_DIR/trace" \
    -e trace=%process \
    --absolute-timestamps=format:unix,precision:us\
    --decode-fds=path \
    --string-limit=4096 \
    --always-show-pid \
    --decode-pids=comm)
fi

# --- Phase 3: Execute Bats ---

# Check if the Bats executable exists.
if [ ! -x "$BATS_EXECUTABLE" ]; then
  echo "Bats executable not found or not executable: $BATS_EXECUTABLE"
  exit 1
fi

# Assemble the final command, explicitly passing --tempdir to bats.
FINAL_CMD=("${STRACE_CMD[@]}" "$BATS_EXECUTABLE" --timing "${BATS_ARGS[@]}" --tempdir "$BATS_RUN_TMPDIR")

echo "Running command: '${FINAL_CMD[*]}'"
echo "Applying memory limit (virtual memory): ${MEMORY_LIMIT_KB} KiB" >&2

# We run the command inside a subshell (...)
# This ensures the ulimit setting only applies to this command
# and does not affect the rest of this script (e.g., Phase 4).
(
  # Set the hard limit for virtual memory (-v) in KiB.
  # If the process exceeds this, it will be killed.
  ulimit -v "$MEMORY_LIMIT_KB"
  #ulimit -u 1024
  "${FINAL_CMD[@]}"
)


# --- Phase 4: Post-Processing ---
if [[ "${CURLPILOT_TRACE:-}" == "true" ]]; then
  #echo "Processing trace data from $SESSION_TMPDIR..." >&2
  # Pass the correct log directories to the analysis scripts.
  bash ./src/tracing/collapsed_stack.bash "$BATS_RUN_TMPDIR"
  bash ./src/tracing/trace_event.bash "$BATS_RUN_TMPDIR"
  bash ./src/tracing/strace/collapsed_stack.bash "$STRACE_LOG_DIR" > "$BATS_RUN_TMPDIR/collapsed_stack.txt"
fi

# bash ./src/tracing/strace/collapsed_stack.bash /tmp/tmp.ULE8Mo2737/strace-logs/
