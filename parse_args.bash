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
HELP_SCRIPT="$SCRIPT_DIR/generate_help_text.jq"

if [[ ! -f "$MAIN_PARSER_SCRIPT" ]]; then
    echo "Error: The required script 'parse_args.jq' was not found in the same directory." >&2
    exit 1
fi

if [[ ! -f "$HELP_SCRIPT" ]]; then
    echo "Error: The required script 'generate_help_text.jq' was not found in the same directory." >&2
    exit 1
fi

JSON_INPUT=$1
SPEC_JSON=$(echo "$JSON_INPUT" | jq -c '.spec')
ARGS_JSON=$(echo "$JSON_INPUT" | jq -c '.args')

if echo "$ARGS_JSON" | jq --exit-status '. | index("--help")' > /dev/null; then
  # 1. Print the human-readable help text to stderr.
  jq --null-input \
     --slurp \
     --raw-output \
     --argjson spec "$SPEC_JSON" \
     --from-file "$HELP_SCRIPT" >&2

  # 2. Print a valid, machine-readable JSON object to stdout.
  # An empty object is a common convention for "success, but no data."
  echo '{"help_requested": true}'


  # 3. Exit with a success code.
  exit 0
else
  jq --null-input \
      --slurp \
      --raw-input \
      --argjson spec "$SPEC_JSON" \
      --argjson args "$ARGS_JSON" \
      --from-file "$MAIN_PARSER_SCRIPT"
fi
