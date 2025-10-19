#!/bin/bash
set -euo pipefail

#
# A function to generate a collapsed stack format from trace data.
#
# The collapsed stack format consists of one stack trace per line.
# Semicolons separate stack frames, and the line ends with an integer
# indicating the weight of that sample.
#
# Example output:
#   root;child_a;leaf_1 100
#   root;child_b;leaf_2 250
#
# Arguments:
#   $1: trace_root - The root directory of the trace data.
#   $2: metric     - The metric to use for the weight. Can be 'wall' or 'cpu'.
#
collapsed_stack_from_trace_root() {
  local trace_root="$1"
  local metric="$2"
  local metric_key

  # Check for required arguments
  if [[ -z "$trace_root" || -z "$metric" ]]; then
    echo "Usage: gemini_collapsed_stack_from_trace_root <trace_root> <wall|cpu>" >&2
    return 1
  fi

  # Determine the JSON key for the metric based on the second argument
  case "$metric" in
    wall)
      metric_key="wall_duration_us"
      ;; 
    cpu)
      metric_key="cpu_duration_us"
      ;; 
    *)
      echo "Invalid metric: '$metric'. Please use 'wall' or 'cpu'." >&2
      return 1
      ;; 
  esac

  # Ensure jq is installed, as it's required for JSON parsing.
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install jq to proceed." >&2
    return 1
  fi

  # Find all 'record.ndjson' files, sort their paths alphabetically,
  # and then concatenate their contents in that sorted order. This is
  # crucial for producing an ordered stack trace.
  # We use `find...-print0 | sort -z | xargs -0` for safe handling of
  # filenames with spaces or special characters.
  find "$trace_root" -name record.ndjson -print0 | sort -z | xargs -0 --no-run-if-empty cat | \
    jq -r \
      --arg key "$metric_key" \
      ' 
      # Filter for entries that have a non-null and positive value for the specified metric.
      select(.data[$key] != null and .data[$key] > 0) | 
      # Format the output string:
      # 1. Take the "id" field and replace all "/" with ";".
      # 2. Append a space.
      # 3. Append the integer value of the metric.
      "\(.id | gsub("/" ; ";")) \(.data[$key])" 
      '
}

if [[ -z "${1-}" ]]; then
  echo "Usage: $0 <trace_root>" >&2
  exit 1
fi

trace_root="$1"

#echo "Generating wall" >&2
collapsed_stack_from_trace_root "$trace_root" wall > "$trace_root/collapsed-stacks-wall.txt" || true
#echo "Generating cpu" >&2
collapsed_stack_from_trace_root "$trace_root" cpu > "$trace_root/collapsed-stacks-cpu.txt" || true
