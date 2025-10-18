#!/bin/bash
#run_tests.bash
set -euo pipefail

source ~/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/src/profiling/profile.bash

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define and export a stable path to the BATS libraries.
# This allows test files to safely override PROJECT_ROOT for sandboxing.
export BATS_LIBS_DIR="$SCRIPT_DIR/libs"

# Define the Bats executable path in terms of the libs directory.
BATS_EXECUTABLE="$BATS_LIBS_DIR/bats/bin/bats"

# Initialize variables.
export CURLPILOT_LOG_LEVEL="${CURLPILOT_LOG_LEVEL:-ERROR}"
export CURLPILOT_LOG_LEVEL_BATS="${CURLPILOT_LOG_LEVEL_BATS:-ERROR}"

export BATS_NUMBER_OF_PARALLEL_JOBS=1
BATS_ARGS=()

# Parse arguments to find the --jobs flag and set our environment variable.
# Pass all other arguments through to BATS.
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -j|--jobs)
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
      echo "Tracing enabled." >&2
      BATS_ARGS+=(--no-tempdir-cleanup)
      shift # Consume the --trace flag, do not pass it to BATS.
      ;;
    *)
      BATS_ARGS+=("$1")
      shift
      ;;
  esac
done

# Check if the Bats executable exists.
if [ ! -x "$BATS_EXECUTABLE" ]; then
  echo "Bats executable not found or not executable: $BATS_EXECUTABLE"
  exit 1
fi

: "${BATS_RUN_TMPDIR:="$(mktemp -du)"}"

echo "Running command: '$BATS_EXECUTABLE' --timing '${BATS_ARGS[*]}'"
"$BATS_EXECUTABLE" --timing "${BATS_ARGS[@]}" --tempdir "$BATS_RUN_TMPDIR"


if [[ "${CURLPILOT_TRACE:-}" == "true" && -f src/tracing/collapsed_stack.bash ]]; then
  source src/tracing/collapsed_stack.bash
  # Find suite trace roots only under the BATS run tmpdir
  while IFS= read -r trace_root; do
    [[ -z "$trace_root" ]] && continue
     collapsed_stack_from_trace_root "$trace_root" wall > "$trace_root/copilot-collapsed-stacks-wall.txt" || true
     collapsed_stack_from_trace_root "$trace_root" cpu > "$trace_root/copilot-collapsed-stacks-cpu.txt" || true
  done < <(find "$BATS_RUN_TMPDIR" -type f -name .suite_id -printf '%h\n')
fi


if [[ "${CURLPILOT_TRACE:-}" == "true" && -f src/tracing/gemini_collapsed_stack.bash ]]; then
  source src/tracing/gemini_collapsed_stack.bash
  # Find suite trace roots only under the BATS run tmpdir
  while IFS= read -r trace_root; do
    [[ -z "$trace_root" ]] && continue
    gemini_collapsed_stack_from_trace_root "$trace_root" wall > "$trace_root/gemini-collapsed-stacks-wall.txt" || true
    gemini_collapsed_stack_from_trace_root "$trace_root" cpu > "$trace_root/gemini-collapsed-stacks-cpu.txt" || true
  done < <(find "$BATS_RUN_TMPDIR" -type f -name .suite_id -printf '%h\n')
fi

if [[ "${CURLPILOT_TRACE:-}" == "true" && -f src/tracing/grok_collapsed_stack.bash ]]; then
  source src/tracing/grok_collapsed_stack.bash
  # Find suite trace roots only under the BATS run tmpdir
  while IFS= read -r trace_root; do
    [[ -z "$trace_root" ]] && continue
    grok_collapsed_stack_from_trace_root "$trace_root" wall > "$trace_root/grok-collapsed-stacks-wall.txt" || true
    grok_collapsed_stack_from_trace_root "$trace_root" cpu > "$trace_root/grok-collapsed-stacks-cpu.txt" || true
  done < <(find "$BATS_RUN_TMPDIR" -type f -name .suite_id -printf '%h\n')
fi

#echo "BATS_RUN_TMPDIR $BATS_RUN_TMPDIR"
