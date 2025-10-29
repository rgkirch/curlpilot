#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

export AWKPATH="$SCRIPT_DIR/lib"

bash "$SCRIPT_DIR/000_run_pipeline.bash" "$@" |
  jq -s -f "$SCRIPT_DIR/200_hierarchy.jq" |
  jq -r -L "$SCRIPT_DIR" -f "$SCRIPT_DIR/process_all.jq"
