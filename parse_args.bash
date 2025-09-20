# parse_args.bash

# This script is a wrapper that dispatches to one of two jq scripts.
# - If --help is present, it calls generate_help_text.jq.
# - Otherwise, it calls parse_args.jq for normal processing.
#
# It requires one argument: a JSON string '{ "spec": {...}, "args": [...] }'.
# Standard input is passed through to the jq process.

# Exit on unset variables and ensure pipeline failures are caught.
set -u -o pipefail


# --- 1. PRE-FLIGHT CHECKS AND PATH SETUP ---

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it to run this script." >&2
    exit 1
fi

# Check for the correct number of arguments
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 '{\"spec\": {...}, \"args\": [...] }'" >&2
    exit 1
fi

# Reliably find the directory where this bash script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MAIN_PARSER_SCRIPT="$SCRIPT_DIR/parse_args.jq"
HELP_SCRIPT="$SCRIPT_DIR/generate_help_text.jq"

# Check if the required jq scripts exist in the same directory
if [[ ! -f "$MAIN_PARSER_SCRIPT" ]]; then
    echo "Error: The required script 'parse_args.jq' was not found in the same directory." >&2
    exit 1
fi
if [[ ! -f "$HELP_SCRIPT" ]]; then
    echo "Error: The required script 'generate_help_text.jq' was not found in the same directory." >&2
    exit 1
fi


# --- 2. ARGUMENT EXTRACTION ---

JSON_INPUT=$1
SPEC_JSON=$(echo "$JSON_INPUT" | jq -c '.spec')
ARGS_JSON=$(echo "$JSON_INPUT" | jq -c '.args')


# --- 3. DISPATCH LOGIC ---

# Check if --help exists in the args array using jq's exit code
if echo "$ARGS_JSON" | jq --exit-status '. | index("--help")' > /dev/null; then
  # If --help is found, run the help generator script.
  # It only needs the spec to generate the help text.
  jq --null-input \
      --raw-output \
      --argjson spec "$SPEC_JSON" \
      --from-file "$HELP_SCRIPT"
else
  # Otherwise, run the main parser script for normal execution.
  # It needs both the spec and the args.
  jq --null-input \
      --raw-input \
      --argjson spec "$SPEC_JSON" \
      --argjson args "$ARGS_JSON" \
      --from-file "$MAIN_PARSER_SCRIPT"
fi
