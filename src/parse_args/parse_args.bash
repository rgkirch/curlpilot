# parse_args/parse_args.bash

set -euo pipefail
#set -x


source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"
register_dep schema_validator "schema_validator.bash"

_main_parse() {
  declare PARSED_VALUES_JSON
  if ! PARSED_VALUES_JSON=$(
      jq --null-input \
         --slurp \
         --raw-input \
         --argjson spec "$SPEC_JSON" \
         --argjson args "$ARGS_JSON" \
         --from-file "$MAIN_PARSER_SCRIPT"
  ); then
      log_error "Error: The jq argument parser failed."
      exit 1
  fi

  jq -c 'to_entries[] | select(.value.schema?) | {arg_name: .key, schema: .value.schema}' <<< "$SPEC_JSON" | \
  while read -r validation_task; do
      log_trace "$$ $? validation_task $validation_task"
      arg_name=$(jq -r '.arg_name' <<< "$validation_task")
      log_trace "$$ $? arg_name $arg_name"
      schema=$(jq -r '.schema' <<< "$validation_task")
      log_trace "$$ $? schema $schema"

      data_to_validate=$(jq --compact-output --arg key "$arg_name" '.[$key]' <<< "$PARSED_VALUES_JSON")
      log_trace "$$ $? data_to_validate $data_to_validate"

      log_trace "Validating argument --$arg_name against schema: $schema"

      resolved_schema_path=$(resolve_path "$schema")
      log_trace "$$ $? resolved_schema_path $resolved_schema_path"

      if ! echo "$data_to_validate" | exec_dep schema_validator "$resolved_schema_path"; then
          log_error "Error: Schema validation failed for argument --$arg_name"
          exit 1
      fi
  done

  log_debug "PARSED_VALUES_JSON $PARSED_VALUES_JSON"

  echo "$PARSED_VALUES_JSON"
}


# --- Main Script Execution ---

if ! command -v jq &> /dev/null; then
    log_error "Error: jq is not installed..."
    exit 1
fi
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 '{\"spec\": {...}, \"args\": [...] }'" >&2
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MAIN_PARSER_SCRIPT="$SCRIPT_DIR/parse_args.jq"
HELP_SCRIPT="$SCRIPT_DIR/../generate_help_text.jq"

JSON_INPUT=$1
SPEC_JSON=$(echo "$JSON_INPUT" | jq --compact-output '.spec')
ARGS_JSON=$(echo "$JSON_INPUT" | jq --compact-output '.args')

HELP_CHECK_FILTER='( (index("--") // length) as $end | .[0:$end] | index("--help") ) != null'
if echo "$ARGS_JSON" | jq --exit-status "$HELP_CHECK_FILTER" > /dev/null; then
  jq --null-input --slurp --raw-output --argjson spec "$SPEC_JSON" --from-file "$HELP_SCRIPT" >&2
  echo '{"help_requested": true}'
  exit 0
else
  _main_parse
fi
