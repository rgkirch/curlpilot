# test/mock/server/launch_copilot.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

BLOCKING_SERVER_SCRIPT=$(path_relative_to_here "blocking_copilot.bash")

# This script only needs to parse its own logging flags and the child args.
readonly ARG_SPEC_JSON='{
  "stderr_log": { "type": "string", "default": "/dev/null" },
  "child_args": { "type": "json", "default": "[]" }
}'

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

readonly STDERR_LOG=$(jq --raw-output '.stderr_log' <<< "$PARSED_ARGS")
readonly CHILD_ARGS_JSON=$(jq --compact-output '.child_args' <<< "$PARSED_ARGS")

child_args_array=()
mapfile -t child_args_array < <(jq --raw-output '.[]' <<< "$CHILD_ARGS_JSON")

# The launcher now chooses the port.
PORT=$(shuf -i 20000-65000 -n 1)

# Launch the blocking server in the background, adding --port to its arguments.
(
  exec bash "$BLOCKING_SERVER_SCRIPT" --port "$PORT" "${child_args_array[@]}"
) 2> "$STDERR_LOG" &
SERVER_PID=$!

# Since we already know the port, we can report it immediately.
echo "$PORT"
echo "$SERVER_PID"
