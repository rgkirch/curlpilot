#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ -z "${1-}" ]]; then
    echo "Usage: $0 JOB_TICKET_JSON" >&2
    exit 1
fi
readonly JOB_TICKET_JSON="$1"
readonly PARSER_SCRIPT="parse_args.jq"

# The wrapper now just pipes stdin directly to jq.
# The jq script will decide whether or not to read it using the `input` builtin.
# We use the -n flag because the primary input is now an argument, not stdin.
output_json=$(jq \
  --null-input \
  --argjson ticket "$JOB_TICKET_JSON" \
  --from-file "$PARSER_SCRIPT"
)

# The help-handling logic remains the same
if jq --exit-status '.is_help == true' <<< "$output_json" > /dev/null; then
  jq --raw-output '.message' <<< "$output_json"
  exit 0
else
  echo "$output_json"
fi
