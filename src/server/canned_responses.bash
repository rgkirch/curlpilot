# src/server/canned-responses.bash

#set -euo pipefail

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
  }
}'

PARSED=$(exec_dep parse_args "$@")
CONFORMED=$(exec_dep conform_args --spec-json "$ARG_SPEC_JSON" --parsed-json "$PARSED")

log "CONFORMED $CONFORMED"

PORT=$(jq -r '.port' <<< "$CONFORMED")
RESPONSES_JSON=$(jq -c '.responses' <<< "$CONFORMED")

if [[ -z "$RESPONSES_JSON" || "$RESPONSES_JSON" == "null" ]]; then
  echo "No responses provided" >&2
  exit 1
fi

mapfile -t RESPONSE_FILES < <(jq -r '.[]' <<< "$RESPONSES_JSON")
for f in "${RESPONSE_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Response file not found: $f" >&2
    exit 1
  fi
done

REQUEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}/requests"
mkdir -p "$REQUEST_DIR"
PROJECT_ROOT=$(get_project_root)

# Serve each response sequentially, one connection per file. After last, exit.
req_index=0
for resp in "${RESPONSE_FILES[@]}"; do
  request_log_file="$REQUEST_DIR/request.$req_index.log"
  log "starting listener index=$req_index resp=$resp port=$PORT log=$request_log_file"
  # Use pipeline form so handler starts only after client connects
  socat -v -T30 TCP4-LISTEN:"$PORT",reuseaddr - \
    | bash -c "set -euo pipefail; source '$PROJECT_ROOT/deps.bash'; log 'handler start index=$req_index resp=$resp'; register_dep handle_request 'server/handle_request.bash'; exec_dep handle_request '$request_log_file' '$resp'; rc=$?; log 'handler done index=$req_index rc='$rc''; exit $rc" || log "socat/handler pipeline exited non-zero index=$req_index code=$?"
  log "finished listener index=$req_index resp=$resp"
  ((++req_index))
done

echo "$REQUEST_DIR"

