#!/bin/bash
set -euo pipefail

#
# A schema-driven argument parser that converts command-line flags to a JSON object.
#
# Usage: ./argument_parser.sh <spec_json> [raw_args...]
#
# This script uses the schema to intelligently parse arguments, correctly
# distinguishing between boolean flags and options that require a value.
# It handles defaults, required checks, and help text generation.
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


# --- MAIN LOGIC ---

# 1. Input validation
[[ "$#" -lt 1 ]] && abort "Argument specification JSON is required."
ARG_SPEC_JSON="$1"
shift

# Check if the spec is valid JSON
echo "$ARG_SPEC_JSON" | jq -e . >/dev/null || abort "Argument specification is not valid JSON."


# 2. Help Generation
for arg in "$@"; do
  if [[ "$arg" == "--help" ]]; then
    echo "Usage: [options]"
    echo ""
    echo "Options:"
    echo "$ARG_SPEC_JSON" | jq -r 'keys[] as $key | "  --\( ($key | gsub("_"; "-")) )\t\(.[$key].description // "")"'
    exit 0
  fi
done


# 3. Parsing Raw Arguments (with Schema Context)
RAW_ARGS_JSON="{}"
while [[ "$#" -gt 0 ]]; do
  ARG="$1"
  shift

  [[ "$ARG" != --* ]] && abort "Invalid argument format: $ARG. Must start with --."

  ARG_NAME_KEBAB="${ARG#--}"
  VALUE=""

  # Handle --key=value format
  if [[ "$ARG_NAME_KEBAB" == *"="* ]]; then
    VALUE="${ARG_NAME_KEBAB#*=}"
    ARG_NAME_KEBAB="${ARG_NAME_KEBAB%%=*}"
  fi

  ARG_NAME_SNAKE=$(kebab_to_snake "$ARG_NAME_KEBAB")

  # --- CONTEXT-AWARE PARSING ---
  IS_IN_SPEC=$(echo "$ARG_SPEC_JSON" | jq --arg key "$ARG_NAME_SNAKE" 'has($key)')
  [[ "$IS_IN_SPEC" == "false" ]] && abort "Unknown option '--$ARG_NAME_KEBAB'."

  ARG_TYPE=$(echo "$ARG_SPEC_JSON" | jq -r --arg key "$ARG_NAME_SNAKE" '.[$key].type')

  # If the arg takes a value AND its value is still empty, consume the next token.
  if [[ "$ARG_TYPE" != "boolean" && -z "$VALUE" ]]; then
    [[ "$#" -eq 0 ]] && abort "Argument '--$ARG_NAME_KEBAB' requires a value."
    VALUE="$1"
    shift
  fi

  # If VALUE is *still* empty, it must be a standalone boolean flag.
  if [[ -z "$VALUE" ]]; then
    VALUE="true"
  fi

  # Use the schema to determine how to process the value
  case "$ARG_TYPE" in
    boolean|number)
      RAW_ARGS_JSON=$(echo "$RAW_ARGS_JSON" | jq --arg key "$ARG_NAME_SNAKE" --argjson val "$VALUE" '.[$key] = $val')
      ;;
    string|path)
      RAW_ARGS_JSON=$(echo "$RAW_ARGS_JSON" | jq --arg key "$ARG_NAME_SNAKE" --arg val "$VALUE" '.[$key] = $val')
      ;;
    *)
      abort "Unsupported type '$ARG_TYPE' in schema for key '$ARG_NAME_SNAKE'."
      ;;
  esac
done


# 4. Final Validation, Defaults, and Required Checks
FINAL_JSON="{}"
SPEC_KEYS=$(echo "$ARG_SPEC_JSON" | jq -r 'keys[]')

for key in $SPEC_KEYS; do
  # Check if user provided the arg
  if [[ $(echo "$RAW_ARGS_JSON" | jq --arg key "$key" 'has($key)') == "true" ]]; then
    # PROBLEM: This pulls the value out of JSON, potentially into a badly quoted
    # shell variable.
    VALUE=$(echo "$RAW_ARGS_JSON" | jq --arg key "$key" '.[$key]')
    # FATAL FLAW: Re-inserting the value with --argjson fails if the shell
    # variable VALUE contains single quotes, like in your '--help' test case.
    FINAL_JSON=$(echo "$FINAL_JSON" | jq --arg key "$key" --argjson val "$VALUE" '.[$key] = $val')
  else
    # This part used the less efficient jq calls you pointed out.
    IS_REQUIRED=$(echo "$ARG_SPEC_JSON" | jq -r --arg key "$key" '.[$key].required // false')
    DEFAULT_VALUE=$(echo "$ARG_SPEC_JSON" | jq --arg key "$key" '.[$key].default')

    if [[ "$IS_REQUIRED" == "true" ]]; then
      abort "Required argument '--$(snake_to_kebab "$key")' is missing."
    fi

    if [[ "$DEFAULT_VALUE" != "null" ]]; then
      FINAL_JSON=$(echo "$FINAL_JSON" | jq --arg key "$key" --argjson val "$DEFAULT_VALUE" '.[$key] = $val')
    fi
  fi
done

# --- OUTPUT ---
echo "$FINAL_JSON"
