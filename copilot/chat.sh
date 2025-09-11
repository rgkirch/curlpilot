#!/bin/env bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

source deps.sh

# Register dependencies
register copilot_request "copilot/request.sh"
register arg_parser "parse_args.sh"
register schema_validator "schema_validator.sh"
register parse_response "copilot/parse_response.sh"
register copilot_config "copilot/config.sh"
source_dep copilot_config
register config "config.sh"
source_dep config

# Define the argument specification for this script, using defaults from config.
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


# --- Argument Parsing and Validation ---
# 1. Parse the raw command-line arguments into a JSON object.
RAW_ARGS_JSON=$(exec_dep arg_parser "$@")

# 2. Validate the raw JSON against the schema to apply defaults and get final parameters.
PARAMS_JSON=$(exec_dep schema_validator "$ARG_SPEC_JSON" "$RAW_ARGS_JSON")
# --- End of Argument Handling ---


# Prepare the request body for the GitHub Copilot API
jq \
  --slurp \
  --argjson options "$(echo "$PARAMS_JSON" | jq 'if .stream != null then .stream_enabled = .stream | del(.stream) else . end')" \
  '($options | {model, stream_enabled}) + {messages: .}' \
| exec_dep copilot_request \
| exec_dep parse_response

echo
