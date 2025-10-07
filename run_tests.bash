#!/bin/bash
set -euo pipefail

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BATS_EXECUTABLE="$PROJECT_ROOT/libs/bats/bin/bats"

# Initialize variables.
export CURLPILOT_LOG_LEVEL="${CURLPILOT_LOG_LEVEL:-ERROR}" # Default to ERROR for clean output
BATS_ARGS=()

# Allow the --verbose flag to enable INFO level logging.
for arg in "$@"; do
  if [[ "$arg" == "--verbose" ]]; then
    export CURLPILOT_LOG_LEVEL=INFO
    echo "Log level set to INFO" >&2
    BATS_ARGS+=(--verbose-run)
  else
    BATS_ARGS+=("$arg")
  fi
done

# Check if the Bats executable exists.
if [ ! -x "$BATS_EXECUTABLE" ]; then
  echo "Bats executable not found or not executable: $BATS_EXECUTABLE"
  exit 1
fi

# Run bats with all the collected arguments.
echo "Running command: CURLPILOT_LOG_LEVEL=$CURLPILOT_LOG_LEVEL '$BATS_EXECUTABLE' --timing '${BATS_ARGS[@]}'"
"$BATS_EXECUTABLE" --timing "${BATS_ARGS[@]}"
