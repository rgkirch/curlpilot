# src/server/launch_server.bash
# New launcher using specless parse + conform.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args_specless.bash"
register_dep conform_args "parse_args/conform_args.bash"
register_dep serialize_args "parse_args/serialize_args.bash"

# Spec for launcher itself + child server
readonly ARG_SPEC_JSON='{
  "server_script": {"type": "path", "default": "canned_responses.bash", "description": "Server script path (relative to this dir or absolute)."},
  "stdout_log": {"type": "path", "default": "/dev/null", "description": "Stdout log target for child."},
  "stderr_log": {"type": "path", "default": "/dev/null", "description": "Stderr log target for child."},
  "port": {"type": "integer", "description": "Port to listen on (random if omitted)."},
  "responses": {"type": "json", "description": "JSON array of response file paths (passed through)."},
  "request_dir": {"type": "string", "description": "Directory for request logs (passed through)."}
}'

for a in "$@"; do
  log "arg $a"
done

# 1. Specless parse of raw args
PARSED=$(exec_dep parse_args "$@")

log "PARSED $PARSED"

# 2. Inject random port if absent
has_port=$(jq 'has("port")' <<< "$PARSED")
if [[ "$has_port" != "true" ]]; then
  log "adding random port"
  rp=$(shuf -i 20000-65000 -n 1)
  PARSED=$(jq --argjson p "$rp" '. + {port: $p}' <<< "$PARSED")
  log "PARSED $PARSED"
fi

# 3. Conform against spec
CONFORMED=$(bash "$(resolve_path src/parse_args/conform_args.bash)" --spec-json "$ARG_SPEC_JSON" --parsed-json "$PARSED")

log "CONFORMED $CONFORMED"

PORT=$(jq -r '.port' <<< "$CONFORMED")
SERVER_SCRIPT_RAW=$(jq -r '.server_script' <<< "$CONFORMED")
STDOUT_LOG=$(jq -r '.stdout_log' <<< "$CONFORMED")
STDERR_LOG=$(jq -r '.stderr_log' <<< "$CONFORMED")

# 4. Resolve server script path
if [[ "$SERVER_SCRIPT_RAW" = /* ]]; then
  SERVER_SCRIPT="$SERVER_SCRIPT_RAW"
else
  SERVER_SCRIPT="$(path_relative_to_here "$SERVER_SCRIPT_RAW")"
fi
[[ -f "$SERVER_SCRIPT" ]] || { echo "Server script not found: $SERVER_SCRIPT" >&2; exit 1; }

# 5. Filter launcher-specific args from the original parsed JSON
CHILD_ARGS_JSON=$(jq 'del(.server_script)' <<< "$PARSED")

# 7. Safely load the JSON array string into a bash array
CHILD_ARGS=()
mapfile -d $'\0' -t CHILD_ARGS < <(jq --raw-output0 'to_entries | map("--" + .key, .value) | flatten | .[]' <<< "$CHILD_ARGS_JSON")

log "CHILD_ARGS ${CHILD_ARGS[*]}"

for arg in "${CHILD_ARGS[@]}"; do
  log "child arg $arg"
done


log "Launching $SERVER_SCRIPT on $PORT"
(
  exec bash "$SERVER_SCRIPT" "${CHILD_ARGS[@]}"
) >"$STDOUT_LOG" 2>"$STDERR_LOG" &
PID=$!

# Passive readiness loop (avoid consuming a connection)
for i in {1..100}; do
  if ! kill -0 "$PID" 2>/dev/null; then
    log "Child exited prematurely"; break
  fi
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn "( sport = :$PORT )" 2>/dev/null | grep -q ":$PORT"; then
      break
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -q "$PORT"; then
      break
    fi
  else
    sleep 0.1; break
  fi
  sleep 0.05
done

echo "$PORT"
echo "$PID"
