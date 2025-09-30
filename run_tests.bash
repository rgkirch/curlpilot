#!/bin/bash
set -euo pipefail

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BATS_EXECUTABLE="$PROJECT_ROOT/libs/bats/bin/bats"

# Initialize variables
CURLPILOT_LOG_TARGET=0
BATS_ARGS=()

for arg in "$@"; do
  if [[ "$arg" == "--verbose" ]]; then
    CURLPILOT_LOG_TARGET=3
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
echo "Running command: CURLPILOT_LOG_TARGET=$CURLPILOT_LOG_TARGET '$BATS_EXECUTABLE' --timing '${BATS_ARGS[@]}'"
CURLPILOT_LOG_TARGET=$CURLPILOT_LOG_TARGET "$BATS_EXECUTABLE" --timing "${BATS_ARGS[@]}"
