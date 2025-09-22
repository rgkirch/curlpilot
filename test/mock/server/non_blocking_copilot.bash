# test/mock/server/non_blocking_copilot.bash
set -euo pipefail

# This script is an asynchronous wrapper that accepts its own flags and
# passes a JSON array of arguments to the blocking server.

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

BLOCKING_SERVER_SCRIPT=$(path_relative_to_here "blocking_copilot.bash")

# 1. Define the launcher's arguments, including '--child-args'.
readonly ARG_SPEC_JSON='{
  "stderr_log": {
    "type": "string",
    "description": "File to write server stderr. Defaults to /dev/null.",
    "default": "/dev/null"
  },
  "child_args": {
    "type": "json",
    "description": "A JSON array of arguments to pass to the blocking server.",
    "default": "[]"
  }
}'

# 2. Parse the launcher's arguments.
job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

readonly STDERR_LOG=$(jq --raw-output '.stderr_log' <<< "$PARSED_ARGS")
readonly CHILD_ARGS_JSON=$(jq --compact-output '.child_args' <<< "$PARSED_ARGS")

# 3. Convert the JSON array string into a proper Bash array.
child_args_array=()
mapfile -t child_args_array < <(jq --raw-output '.[]' <<< "$CHILD_ARGS_JSON")

port_file=$(mktemp)
trap 'rm -f "$port_file"' EXIT

# 4. Launch the blocking server, passing the expanded Bash array as arguments.
(
  exec bash "$BLOCKING_SERVER_SCRIPT" "${child_args_array[@]}"
) > "$port_file" 2> "$STDERR_LOG" &
SERVER_PID=$!

# Wait for and report the port and PID.
for _ in $(seq 1 20); do
    [[ -s "$port_file" ]] && break; sleep 0.1
done
PORT=$(cat "$port_file")
if [[ -z "$PORT" ]]; then
  echo "Error: Timed out waiting for server to report its port." >&2
  kill "$SERVER_PID"; exit 1
fi
echo "$PORT"
echo "$SERVER_PID"
