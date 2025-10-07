#!/bin/bash
# unform.bash
# The inverse of conform_args. Consumes a spec and a conformed JSON object.
# Emits a JSON object where values are coerced back to strings, suitable
# for re-parsing. For 'json' types, the native JSON value is encoded into a string.

set -euo pipefail

SOURCE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$SOURCE_DIR/.deps.bash"

usage() {
  echo "Usage: $0 --spec-json '<json>' --parsed-json '<json>'" >&2
  exit 1
}

SPEC_JSON=""
# The --parsed-json for this script is the CONFORMED json from the other script.
CONFORMED_JSON=""
while (( $# )); do
  case "$1" in
    --spec-json)
      shift; SPEC_JSON="${1:-}" || true;;
    --parsed-json)
      shift; CONFORMED_JSON="${1:-}" || true;;
    *) usage ;;
  esac
  shift || true
done

[[ -n "$SPEC_JSON" && -n "$CONFORMED_JSON" ]] || usage

# Quick sanity checks
if ! echo "$SPEC_JSON" | jq -e . >/dev/null 2>&1; then
  echo "unform_args: spec is not valid JSON" >&2; exit 1; fi
if ! echo "$CONFORMED_JSON" | jq -e . >/dev/null 2>&1; then
  echo "unform_args: conformed data is not valid JSON" >&2; exit 1; fi

# Build output object incrementally.
UNFORMED_OUTPUT='{}'

# Iterate spec keys preserving insertion order
while IFS= read -r key; do
  # Skip keys that are not present in the conformed input
  if ! echo "$CONFORMED_JSON" | jq -e --arg k "$key" 'has($k)' >/dev/null; then
    continue
  fi

  spec_entry=$(echo "$SPEC_JSON" | jq -c --arg k "$key" '.[$k]')
  type=$(echo "$spec_entry" | jq -r '.type')
  conformed_value=$(echo "$CONFORMED_JSON" | jq -c --arg k "$key" '.[$k]')

  # Coerce back to string representations based on type
  case "$type" in
    json)
      # Encode the native JSON value into a JSON string
      string_val_json=$(echo "$conformed_value" | jq -c 'tojson')
      ;;
    boolean|number|integer)
      # Convert native bools/numbers to their string representation
      string_val_json=$(echo "$conformed_value" | jq -c 'tostring')
      ;;
    *)
      # For types that are already strings (string, path, enum, regex),
      # the value is already a correctly quoted JSON string.
      string_val_json="$conformed_value"
      ;;
  esac

  # Add the stringified value to the output object
  UNFORMED_OUTPUT=$(jq --arg k "$key" --argjson v "$string_val_json" '. + {($k): $v}' <<< "$UNFORMED_OUTPUT")

done < <(echo "$SPEC_JSON" | jq -r 'keys[]')


echo "$UNFORMED_OUTPUT" | jq -c '.'
