# parse_args.bash
set -euo pipefail
#set -x

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to run this script." >&2
    exit 1
fi

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 '{\"spec\": {...}, \"args\": [...] }'" >&2
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MAIN_PARSER_SCRIPT="$SCRIPT_DIR/parse_args.jq"
HELP_SCRIPT="$SCRIPT_DIR/../generate_help_text.jq"

if [[ ! -f "$MAIN_PARSER_SCRIPT" ]]; then
    echo "Error: The required script 'parse_args.jq' was not found in the same directory." >&2
    exit 1
fi

if [[ ! -f "$HELP_SCRIPT" ]]; then
    echo "Error: The required script 'generate_help_text.jq' was not found in the same directory." >&2
    exit 1
fi

JSON_INPUT=$1
SPEC_JSON=$(echo "$JSON_INPUT" | jq --compact-output '.spec')
ARGS_JSON=$(echo "$JSON_INPUT" | jq --compact-output '.args')

# This jq filter is now smart enough to ignore --help if it comes after a '--'.
HELP_CHECK_FILTER='( (index("--") // length) as $end | .[0:$end] | index("--help") ) != null'

if echo "$ARGS_JSON" | jq --exit-status "$HELP_CHECK_FILTER" > /dev/null; then
  # Print help text to stderr.
  jq --null-input \
     --slurp \
     --raw-output \
     --argjson spec "$SPEC_JSON" \
     --from-file "$HELP_SCRIPT" >&2

  # Print an explicit JSON status object to stdout.
  echo '{"help_requested": true}'
  exit 0
else
  # The jq script for actual parsing.
  jq --null-input \
     --slurp \
     --raw-input \
     --argjson spec "$SPEC_JSON" \
     --argjson args "$ARGS_JSON" \
     --from-file "$MAIN_PARSER_SCRIPT"
fi
