# copilot/chat.bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/deps.bash"

register_dep request "copilot/request.bash"
register_dep parse_args "parse_args.bash"
register_dep schema_validator "schema_validator.bash"
register_dep parse_response "copilot/parse_response.bash"
register_dep copilot_config "copilot/config.bash"
register_dep config "config.bash"

CONFIG=$(exec_dep parse_args)

ARG_SPEC_JSON=$(cat <<EOF
{
  "model": {
    "type": "string",
    "description": "Specify the AI model to use.",
    "default": "$MODEL"
  },
  "api_endpoint": {
    "type": "string",
    "description": "Specify the API endpoint for the chat service.",
    "default": "$API_ENDPOINT"
  },
  "stream": {
    "type": "boolean",
    "description": "Enable or disable streaming responses.",
    "default": $STREAM_ENABLED
  },
  "config_dir": {
    "type": "path",
    "description": "Set the configuration directory.",
    "default": "$CONFIG_DIR"
  },
  "token_file": {
    "type": "path",
    "description": "Set the token file path.",
    "default": "$TOKEN_FILE"
  }
}
EOF
)

jq -n \
  --argjson spec "$ARG_SPEC_JSON" \
  '{"spec": $spec, "args": $ARGS.positional}' \
  --args -- "$@" \
  | exec_dep parse_args

PARAMS_JSON=$(exec_dep schema_validator "$ARG_SPEC_JSON" "$RAW_ARGS_JSON")

jq \
  --slurp \
  --argjson options "$(echo "$PARAMS_JSON" | jq 'if .stream != null then .stream_enabled = .stream | del(.stream) else . end')" \
  '($options | {model, stream_enabled}) + {messages: .}' \
| exec_dep request \
| exec_dep parse_response

echo
