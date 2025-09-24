# test/mock/server/launch_copilot.bash
set -euo pipefail
set -x

log() {
  echo "$(date '+%T.%N') [launch_copilot] $*" >&3
}

log "Script started."

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

log "Arguments parsed: '$PARSED_ARGS'"

if [[ $(jq --raw-output '.help_requested' <<< "$PARSED_ARGS") == "true" ]]; then
  exit 0
fi

readonly STDOUT_LOG=$(jq --raw-output '.stdout_log' <<< "$PARSED_ARGS")
readonly STDERR_LOG=$(jq --raw-output '.stderr_log' <<< "$PARSED_ARGS")
readonly CHILD_ARGS_JSON=$(jq --compact-output '.child_args' <<< "$PARSED_ARGS")

child_args_array=()
mapfile -t child_args_array < <(jq --raw-output '.[]' <<< "$CHILD_ARGS_JSON")

PORT=$(shuf -i 20000-65000 -n 1)

log "Launching blocking server script: $BLOCKING_SERVER_SCRIPT on port $PORT"
(
  exec bash "$BLOCKING_SERVER_SCRIPT" --port "$PORT" "${child_args_array[@]}"
) > "$STDOUT_LOG" 2> "$STDERR_LOG" &
SERVER_PID=$!
log "Server launched with PID: $SERVER_PID"

echo "PORT: $PORT" >> "$STDERR_LOG"
echo "$PORT"
echo "SERVER_PID: $SERVER_PID" >> "$STDERR_LOG"
echo "$SERVER_PID"

log "Script finished."
