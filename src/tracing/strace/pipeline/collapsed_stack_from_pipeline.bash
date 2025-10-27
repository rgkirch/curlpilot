#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

bash "$SCRIPT_DIR/000_run_pipeline.bash" "$@" |
  jq -s -f "$SCRIPT_DIR/200_hierarchy.jq" |
  jq -f "$SCRIPT_DIR/201_link_spans.jq" |
  jq -f "$SCRIPT_DIR/202_with_collapsed_stack.jq" |
  jq -f "$SCRIPT_DIR/203_with_durations.jq" |
  jq -r -f "$SCRIPT_DIR/204_as_collapsed_stack.jq"
