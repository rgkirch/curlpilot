# src/server/canned-responses.bash

set -euo pipefail
#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args_specless.bash"
register_dep conform_args "parse_args/conform_args.bash"
register_dep handle_request "server/handle_request.bash"

readonly ARG_SPEC_JSON='{
  "port": {
    "type": "number",
    "description": "Required. Port to listen on."
  },
  "responses": {
    "type": "json",
    "description": "JSON array of file paths containing full HTTP responses (headers+body)."
  },
  "request_dir": {
    "type": "string",
    "default": null,
    "description": "Optional. Directory to store request logs. If not provided, requests are not logged."
  }
}'

for a in "$@"; do
  log_debug "arg $a"
done

PARSED=$(exec_dep parse_args "$@")
log_debug "PARSED $PARSED"
CONFORMED=$(exec_dep conform_args --spec-json "$ARG_SPEC_JSON" --parsed-json "$PARSED")
log_debug "CONFORMED $CONFORMED"

PORT=$(jq -r '.port' <<< "$CONFORMED")
RESPONSES_JSON=$(jq -c '.responses' <<< "$CONFORMED")
REQUEST_DIR=$(jq -r '.request_dir // ""' <<< "$CONFORMED")

log_debug "RESPONSES_JSON $RESPONSES_JSON"

if [[ -z "$RESPONSES_JSON" || "$RESPONSES_JSON" == "null" ]]; then
  echo "No responses provided" >&2
  exit 1
fi

mapfile -d $'\0' -t RESPONSE_FILES < <(jq --raw-output0 '.[]' <<< "$RESPONSES_JSON")
for f in "${RESPONSE_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Response file not found: $f" >&2
    exit 1
  fi
done

if [[ -n "$REQUEST_DIR" ]]; then
  mkdir -p "$REQUEST_DIR"
fi
PROJECT_ROOT=$(get_project_root)

# Serve each response sequentially, one connection per file. After last, exit.
req_index=0
for resp in "${RESPONSE_FILES[@]}"; do
  
  if [[ -n "$REQUEST_DIR" ]]; then
    request_log_file="$REQUEST_DIR/request.$req_index.log"
  else
    request_log_file="/dev/null"
  fi
  
  log_debug "starting listener index=$req_index resp=$resp port=$PORT log=$request_log_file"

  # Create a temporary, dedicated handler script for this specific request.
  handler_script_path="$(mktemp)"
  cat > "$handler_script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Source the project's dependencies to make 'exec_dep' and 'log' available.
source "$PROJECT_ROOT/deps.bash"
# Register the dependency so exec_dep can find it.
register_dep handle_request "server/handle_request.bash"

log_debug "handler starting for request $req_index"
# Execute the actual handler with the correct arguments for this loop iteration.
exec_dep handle_request "$request_log_file" "$resp"
log_debug "handler finished for request $req_index"
EOF
  chmod +x "$handler_script_path"

  # Use the robust single-shot server pattern.
  log_debug ">>> About to run socat for index $req_index"
  socat -T5 TCP4-LISTEN:"$PORT",reuseaddr,shut-down \
    "SYSTEM:$handler_script_path"
  SOCAT_EXIT_CODE=$?
  log_debug "<<< socat for index $req_index finished with exit code $SOCAT_EXIT_CODE"
  
  rm "$handler_script_path"

  log_debug "finished listener index=$req_index resp=$resp"
  ((++req_index))
done
