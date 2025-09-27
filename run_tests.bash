#!/bin/bash
set -euo pipefail

# Get the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BATS_EXECUTABLE="$PROJECT_ROOT/test/bats/bin/bats"
TEST_DIR="$PROJECT_ROOT/test/mock/test"

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

# Run Bats on all .bats files in the test directory.
# The --timing flag provides detailed output.
"$BATS_EXECUTABLE" --timing "$TEST_DIR"