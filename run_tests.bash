#!/bin/bash
set -euo pipefail

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BATS_EXECUTABLE="$PROJECT_ROOT/test/bats/bin/bats"
TEST_DIR="$PROJECT_ROOT/test/mock/test"

# Initialize CURLPILOT_LOG_TARGET
CURLPILOT_LOG_TARGET=0
BATS_ARGS=()

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--verbose" ]]; then
    CURLPILOT_LOG_TARGET=3
  else
    BATS_ARGS+=("$arg")
  fi
done

# Check if the test directory exists.
if [ ! -d "$TEST_DIR" ]; then
  echo "Test directory not found: $TEST_DIR"
  exit 1
fi

# Check if the Bats executable exists.
if [ ! -x "$BATS_EXECUTABLE" ]; then
  echo "Bats executable not found or not executable: $BATS_EXECUTABLE"
  exit 1
fi

# Run Bats on all .bats files in the test directory with the collected arguments.
# The --timing flag provides detailed output.
CURLPILOT_LOG_TARGET=$CURLPILOT_LOG_TARGET "$BATS_EXECUTABLE" --timing "${BATS_ARGS[@]}" "$TEST_DIR"