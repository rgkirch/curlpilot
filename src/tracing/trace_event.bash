#!/bin/bash
set -euo pipefail

#
# A function to generate the Trace Event Format from trace data.
#
# This format is a JSON object containing an array of events that can be
# loaded into trace viewers like Perfetto for visualization.
# Each record from the input data is converted into a "Complete Event" (`ph: "X"`).
#
# See: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview
#
# Arguments:
#   $1: trace_root - The root directory of the trace data.
#
trace_event_from_trace_root() {
  local trace_root="$1"

  # Check for required arguments
  if [[ -z "$trace_root" ]]; then
    echo "Usage: gemini_trace_event_from_trace_root <trace_root>" >&2
    return 1
  fi

  # Ensure jq is installed, as it's required for JSON parsing.
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install jq to proceed." >&2
    return 1
  fi

  # Find all 'record.ndjson' files, sort their paths alphabetically,
  # and then concatenate their contents in that sorted order.
  # The entire stream is then piped into jq.
  find "$trace_root" -name record.ndjson -print0 | sort -z | xargs -0 --no-run-if-empty cat | \
    jq -s \
    '
    {
      "traceEvents": map(
        # Filter for records that have a valid, non-zero wall-clock duration.
        # The `?` prevents errors if `.data` or `.wall_duration_us` are null.
        select(.data.wall_duration_us? and .data.wall_duration_us > 0) |
        # Transform the record into a Trace Event object.
        {
          name: .name,
          # Use parentId for the category, defaulting to "root".
          cat: (.parentId | if . == "" then "root" else . end),
          # "X" denotes a "Complete Event" with a start time and duration.
          ph: "X",
          # ts is the timestamp in microseconds.
          ts: .data.start_timestamp_us,
          # dur is the duration in microseconds.
          dur: .data.wall_duration_us,
          pid: .pid,
          # Trace Event Format requires a thread ID (tid); we use pid as a substitute.
          tid: .pid,
          # Include the original data object in `args` for detailed inspection in the viewer.
          args: .data
        }
      )
    }
    '
}

if [[ -z "${1-}" ]]; then
  echo "Usage: $0 <trace_root>" >&2
  exit 1
fi

trace_root="$1"
output_file="$trace_root/trace.json"

echo "Generating Trace Event file: $output_file" >&2
trace_event_from_trace_root "$trace_root" > "$output_file" || true