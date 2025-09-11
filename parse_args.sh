#!/bin/bash

set -euo pipefail

#
# A schema-driven argument parser that converts command-line flags to a JSON object.
#
# Usage: ./argument_parser.sh <spec_json> [raw_args...]
#
# This script uses a more declarative, SSA-like (Single Static Assignment) style
# to reduce bugs related to mutable state. Data is transformed from one readonly
# variable to the next.
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

# fail if didn't pass an arg because spec is required as first arg
[[ "$#" -lt 1 ]] && abort "Argument specification JSON is required."
readonly USER_SPEC_JSON="$1"
shift # Consume the spec from the argument list

# fail if first arg, i.e. the spec, isn't json
echo "$USER_SPEC_JSON" | jq -e . >/dev/null || abort "Argument specification is not valid JSON."


# fail if "help" exists in user provided spec
if [[ $(echo "$USER_SPEC_JSON" | jq 'has("help")') == "true" ]]; then
  abort "The argument key 'help' is reserved and cannot be defined in the schema."
fi

# add "help" option to spec
readonly ARG_SPEC_JSON=$(echo "$USER_SPEC_JSON" | jq '. + {"help": {"type": "boolean", "description": "Show this help message and exit."}}')


# --- 2. RAW ARGUMENT PARSING LOOP ---

RAW_ARGS_JSON="{}"

# while there are remaining args not yet consumed
while [[ "$#" -gt 0 ]]; do
  ARG="$1"
  shift

  [[ "$ARG" != --* ]] && abort "Invalid argument format: $ARG."

  # These are temporary, mutable variables for the loop iteration
  arg_name_kebab="${ARG#--}"
  value=""

  if [[ "$arg_name_kebab" == *"="* ]]; then
    # These helpers are now mutable and scoped within the loop
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
      [[ "$#" -eq 0 ]] && abort "Argument '--$arg_name_kebab' requires a value."
      value="$1"
      shift
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

if echo "$RAW_ARGS_JSON" | jq -e '.help == true' > /dev/null; then
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
