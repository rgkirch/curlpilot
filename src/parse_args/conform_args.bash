# conform_args.bash
# Consume a spec JSON and a parsed-args JSON (from parse_args_specless)
# Validate, apply defaults, coerce types, and emit a compact JSON object of the spec keys.
# Unknown parsed args are ignored.
# If a spec key has no default and is absent -> error.
# Types: string, path, regex, enum, json, number, integer, boolean
# enum requires .enums array
# json may contain .schema (path to schema file or embedded JSON object) -> optional validation via schema_validator (if present)

set -euo pipefail
#set -x

SOURCE_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$SOURCE_DIR/.deps.bash"
# schema validator is optional; register if exists
if [[ -f "$SOURCE_DIR/schema_validator.bash" ]]; then
  register_dep schema_validator "parse_args/schema_validator.bash"
fi

log "args $@"

usage() {
  echo "Usage: $0 --spec-json '<json>' --parsed-json '<json>'" >&2
  exit 1
}

SPEC_JSON=""
PARSED_JSON=""
while (( $# )); do
  case "$1" in
    --spec-json)
      shift; SPEC_JSON="${1:-}" || true;;
    --parsed-json)
      shift; PARSED_JSON="${1:-}" || true;;
    *) usage ;;
  esac
  shift || true
done

log "SPEC_JSON $SPEC_JSON and PARSED_JSON $PARSED_JSON"

[[ -n "$SPEC_JSON" && -n "$PARSED_JSON" ]] || usage

log "insane 1"
# Quick sanity checks
if ! echo "$SPEC_JSON" | jq -e . >/dev/null 2>&1; then
  error "conform_args: spec is not valid JSON" >&2; exit 1; fi
if ! echo "$PARSED_JSON" | jq -e . >/dev/null 2>&1; then
  error "conform_args: parsed args is not valid JSON" >&2; exit 1; fi

log "insane 2"
# Build output object incrementally.
OUTPUT='{}'
ERRORS=()

log "insane 3"
# Iterate spec keys preserving insertion order
while IFS= read -r key; do
  log "procesing key $key"
  spec_entry=$(echo "$SPEC_JSON" | jq -c --arg k "$key" '.[$k]')
  type=$(echo "$spec_entry" | jq -r '.type')
  has_default=$(echo "$spec_entry" | jq 'has("default")')
  default_value=$(echo "$spec_entry" | jq -c '.default // empty')

  is_from_default=false
  parsed_present=$(echo "$PARSED_JSON" | jq --arg k "$key" 'has($k)')
  if [[ "$parsed_present" == "true" ]]; then
    raw_value=$(echo "$PARSED_JSON" | jq -c --arg k "$key" '.[$k]')
  else
    if [[ "$has_default" == "true" ]]; then
      raw_value="$default_value"
      is_from_default=true
    else
      ERRORS+=("missing required argument --$key")
      continue
    fi
  fi

  # Coerce according to type
  case "$type" in
    string|path)
      # Ensure raw_value is string
      val=$(echo "$raw_value" | jq -r '.')
      ;;
    boolean)
      # raw_value could be true (literal), or string
      lit=$(echo "$raw_value" | jq -r '.') || lit="$raw_value"
      shopt -s nocasematch || true
      if [[ "$lit" == "true" || "$lit" == "1" ]]; then
        val=true
      elif [[ "$lit" == "false" || "$lit" == "0" ]]; then
        val=false
      else
        # presence boolean with non-standard value -> error
        ERRORS+=("invalid boolean for --$key: $lit")
        continue
      fi
      shopt -u nocasematch || true
      ;;
    number|integer)
      lit=$(echo "$raw_value" | jq -r '.') || lit="$raw_value"
      if [[ "$type" == "integer" ]]; then
        if [[ ! "$lit" =~ ^-?[0-9]+$ ]]; then
          ERRORS+=("--$key must be integer, got '$lit'")
          continue
        fi
      else
        if [[ ! "$lit" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
          ERRORS+=("--$key must be number, got '$lit'")
          continue
        fi
      fi
      val=$lit
      ;;
    enum)
      enums=$(echo "$spec_entry" | jq -c '.enums // empty')
      if [[ -z "$enums" || "$enums" == "null" ]]; then
        ERRORS+=("enum spec for --$key missing 'enums' array")
        continue
      fi
      lit=$(echo "$raw_value" | jq -r '.')
      in_set=$(echo "$enums" | jq --arg v "$lit" 'index($v) // false')
      if [[ "$in_set" == "false" ]]; then
        ERRORS+=("--$key invalid enum value '$lit'")
        continue
      fi
      val="$lit"
      ;;
    regex)
      lit=$(echo "$raw_value" | jq -r '.')
      # Test compile using grep -E (portable enough)
      if ! echo "" | grep -E "$lit" >/dev/null 2>&1; then
        ERRORS+=("--$key invalid regex '$lit'")
        continue
      fi
      val="$lit"
      ;;
    json)
      if [[ "$is_from_default" == "true" ]]; then
        # Contract for defaults: MUST be native JSON.
        if [[ $(echo "$raw_value" | jq 'type') == '"string"' ]]; then
          ERRORS+=("--$key default in spec must be native JSON, but a string was provided")
          continue
        fi
        compact="$raw_value"
      else
        # Contract for parsed args: MUST be a string that we can decode.
        if [[ $(echo "$raw_value" | jq 'type') != '"string"' ]]; then
          ERRORS+=("--$key value from parsed args must be a string, but native JSON was provided")
          continue
        fi
        compact=$(echo "$raw_value" | jq -c 'try fromjson catch "__DECODE_FAIL__"')
        if [[ "$compact" == '"__DECODE_FAIL__"' ]]; then
          ERRORS+=("--$key value contains malformed JSON")
          continue
        fi
      fi

      # Optional schema
      schema_ref=$(echo "$spec_entry" | jq -r '.schema // empty')
      if [[ -n "$schema_ref" ]]; then
        # Determine if schema_ref is object or path
        if echo "$schema_ref" | jq -e . >/dev/null 2>&1 && [[ "$schema_ref" =~ ^\{ ]] ; then
          # Embedded schema object
          if declare -F exec_dep >/dev/null 2>&1 && [[ -n "${SCRIPT_REGISTRY[schema_validator]:-}" ]]; then
            echo "$compact" | exec_dep schema_validator <(echo "$schema_ref") || ERRORS+=("--$key failed schema validation (embedded)")
          fi
        else
          # Treat as path
            resolved_schema=$(resolve_path "$schema_ref" 2>/dev/null || true)
            if [[ -n "$resolved_schema" && -f "$resolved_schema" ]] && declare -F exec_dep >/dev/null 2>&1 && [[ -n "${SCRIPT_REGISTRY[schema_validator]:-}" ]]; then
              echo "$compact" | exec_dep schema_validator "$resolved_schema" || ERRORS+=("--$key failed schema validation ($schema_ref)")
            fi
        fi
      fi
      val_json="$compact"
      ;;
    *)
      ERRORS+=("unsupported type '$type' for --$key")
      continue
      ;;
  esac

  # Add to OUTPUT
  if [[ "$type" == "json" ]]; then
    OUTPUT=$(jq --arg k "$key" --argjson v "$val_json" '. + {($k): $v}' <<< "$OUTPUT")
  elif [[ "$type" == "boolean" ]]; then
    OUTPUT=$(jq --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<< "$OUTPUT")
  elif [[ "$type" == "number" || "$type" == "integer" ]]; then
    OUTPUT=$(jq --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<< "$OUTPUT")
  else
    OUTPUT=$(jq --arg k "$key" --arg v "$val" '. + {($k): $v}' <<< "$OUTPUT")
  fi

done < <(echo "$SPEC_JSON" | jq -r 'keys[]')

if (( ${#ERRORS[@]} )); then
  printf 'conform_args errors:\n' >&2
  for e in "${ERRORS[@]}"; do printf ' - %s\n' "$e" >&2; done
  exit 1
fi

log "OUTPUT $OUTPUT"

log "$(jq '.' <<<"$OUTPUT")"

jq -c '.' <<<"$OUTPUT"
