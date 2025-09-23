# test/mock/server/launch_copilot.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../deps.bash"
register_dep parse_args "parse_args.bash"

BLOCKING_SERVER_SCRIPT=$(path_relative_to_here "copilot.bash")

readonly ARG_SPEC_JSON='{
  "stdout_log": {
    "type": "string",
    "default": "/dev/null",
    "description": "File to write the background server stdout to."
  },
  "stderr_log": {
    "type": "string",
    "default": "/dev/null",
    "description": "File to write the background server stderr to."
  },
  "child_args": {
    "type": "json",
    "default": "[]",
    "description": "A JSON array of arguments to pass to the blocking server."
  }
}'

job_ticket_json=$(jq --null-input --argjson spec "$ARG_SPEC_JSON" '{spec: $spec, args: $ARGS.positional}' --args -- "$@")
PARSED_ARGS=$(exec_dep parse_args "$job_ticket_json")

if [[ $(jq --raw-output '.help_requested' <<< "$PARSED_ARGS") == "true" ]]; then
  exit 0
fi

readonly STDOUT_LOG=$(jq --raw-output '.stdout_log' <<< "$PARSED_ARGS")
readonly STDERR_LOG=$(jq --raw-output '.stderr_log' <<< "$PARSED_ARGS")
readonly CHILD_ARGS_JSON=$(jq --compact-output '.child_args' <<< "$PARSED_ARGS")

child_args_array=()
mapfile -t child_args_array < <(jq --raw-output '.[]' <<< "$CHILD_ARGS_JSON")

PORT=$(shuf -i 20000-65000 -n 1)

(
  exec bash "$BLOCKING_SERVER_SCRIPT" --port "$PORT" "${child_args_array[@]}"
) > "$STDOUT_LOG" 2> "$STDERR_LOG" &
SERVER_PID=$!

echo "$PORT"
echo "$SERVER_PID"