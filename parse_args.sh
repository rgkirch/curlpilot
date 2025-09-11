#!/bin/bash

set -euo pipefail

# curlpilot/parse_args.sh

#
# A schema-driven argument parser that converts a JSON array of arguments
# into a final JSON object based on a provided specification.
#
# Usage:
#   echo '{"spec": {...}, "args": ["--foo", "bar"]}' | ./parse_args.sh
#
# This script reads a single JSON object from stdin and processes it.
#

# --- UTILITY FUNCTIONS ---

# Abort with a message.
abort() {
  echo "Error: $1" >&2
  exit 1
}

# Convert snake_case to kebab-case for command-line flags.
snake_to_kebab() {
  echo "$1" | sed 's/_/-/g'
}

# Convert kebab-case to snake_case for spec keys.
kebab_to_snake() {
  echo "$1" | sed 's/-/_/g'
}

# --- 1. INITIALIZATION & SCHEMA VALIDATION ---

# Read the entire "job ticket" from standard input.
readonly JOB_TICKET_JSON=$(cat)

# Extract the spec and args from the ticket.
readonly USER_SPEC_JSON=$(echo "$JOB_TICKET_JSON" | jq -c '.spec')
ARGS_JSON=$(echo "$JOB_TICKET_JSON" | jq -c '.args')

# Validate that the provided spec is valid JSON.
echo "$USER_SPEC_JSON" | jq -e . >/dev/null || abort "Argument specification is not valid JSON."

# The 'help' key is reserved for the parser's use.
if [[ $(echo "$USER_SPEC_JSON" | jq 'has("help")') == "true" ]]; then
  abort "The argument key 'help' is reserved and cannot be defined in the schema."
fi

# Add the 'help' option to the spec for automatic help generation.
readonly ARG_SPEC_JSON=$(echo "$USER_SPEC_JSON" | jq '. + {"help": {"type": "boolean", "description": "Show this help message and exit."}}')


# --- 2. RAW ARGUMENT PARSING LOOP ---

RAW_ARGS_JSON="{}"

# Loop as long as there are elements in the ARGS_JSON array.
while [[ $(echo "$ARGS_JSON" | jq 'length > 0') == "true" ]]; do
  # Get the first argument from the JSON array.
  ARG=$(echo "$ARGS_JSON" | jq -r '.[0]')
  # Consume the first argument for the next iteration.
  ARGS_JSON=$(echo "$ARGS_JSON" | jq '.[1:]')

  [[ "$ARG" != --* ]] && abort "Invalid argument format: $ARG."

  arg_name_kebab="${ARG#--}"
  value=""

  if [[ "$arg_name_kebab" == *"="* ]]; then
    final_value="${ARG#*=}"
    final_key_kebab="${arg_name_kebab%%=*}"
    value="$final_value"
    arg_name_kebab="$final_key_kebab"
  fi

  arg_name_snake=$(kebab_to_snake "$arg_name_kebab")
  arg_type=$(echo "$ARG_SPEC_JSON" | jq -r --arg key "$arg_name_snake" '.[$key].type // empty')

  [[ -z "$arg_type" ]] && abort "Unknown option '--$arg_name_kebab'."

  if [[ -z "$value" ]]; then
    if [[ "$arg_type" == "boolean" ]]; then
      value="true"
    else
      # Instead of shifting, get the next value from the JSON array.
      if [[ $(echo "$ARGS_JSON" | jq 'length == 0') == "true" ]]; then
        abort "Argument '--$arg_name_kebab' requires a value."
      fi
      value=$(echo "$ARGS_JSON" | jq -r '.[0]')
      ARGS_JSON=$(echo "$ARGS_JSON" | jq '.[1:]')
    fi
  fi

  case "$arg_type" in
    boolean|number|json)
      RAW_ARGS_JSON=$(echo "$RAW_ARGS_JSON" | jq --arg key "$arg_name_snake" --argjson val "$value" '.[$key] = $val')
      ;;
    string|path)
      RAW_ARGS_JSON=$(echo "$RAW_ARGS_JSON" | jq --arg key "$arg_name_snake" --arg val "$value" '.[$key] = $val')
      ;;
    *)
      abort "Unsupported type '$arg_type' in schema for key '$arg_name_snake'."
      ;;
  esac
done

readonly RAW_ARGS_JSON


# --- 3. POST-PARSING ACTIONS (HELP) ---

if echo "$RAW_ARGS_JSON" | jq -e '.help == true' >/dev/null; then
  echo "Usage: [options]"
  echo ""
  echo "Options:"
  echo "$ARG_SPEC_JSON" | jq -r 'keys[] as $key | "  --\( ($key | gsub("_"; "-")) )\t\(.[$key].description // "")"'
  exit 0
fi


# --- 4. APPLY DEFAULTS & CHECK REQUIRED ---

readonly DEFAULTS_JSON=$(echo "$ARG_SPEC_JSON" | jq '
  with_entries(select(.value.default != null)) |
  with_entries(.value = .value.default)
')

readonly FINAL_JSON=$(jq -s '.[0] + .[1]' <(echo "$DEFAULTS_JSON") <(echo "$RAW_ARGS_JSON"))

readonly SPEC_KEYS=$(echo "$ARG_SPEC_JSON" | jq -r 'keys[]')
for key in $SPEC_KEYS; do
  is_required=$(echo "$ARG_SPEC_JSON" | jq -r --arg key "$key" '.[$key].required // false')
  if [[ "$is_required" == "true" ]]; then
    if [[ $(echo "$FINAL_JSON" | jq --arg key "$key" 'has($key)') == "false" ]]; then
      abort "Required argument '--$(snake_to_kebab "$key")' is missing."
    fi
  fi
done


# --- 5. FINAL OUTPUT ---

echo "$FINAL_JSON" | jq 'del(.help)'
