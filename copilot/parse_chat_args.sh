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

register copilot_config "copilot/config.sh"
source_dep copilot_config

register config "config.sh"
source_dep config

# Function to display usage information
usage() {
  echo "Usage: echo '{\"role\": \"user\", \"content\": \"your prompt\"}' | $(basename "$ORIGINAL_SCRIPT_NAME") [options]"
  echo ""
  echo "Options:"
  echo "  --model=<name>        Specify the AI model to use (e.g., gpt-4.1). Default: $MODEL"
  echo "  --api-endpoint=<url>  Specify the API endpoint for the chat service. Default: $API_ENDPOINT"
  echo "  --stream=true|false   Enable or disable streaming responses. Default: $STREAM_ENABLED"
  echo "  --help                Display this help message."
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --stream=true)
      STREAM_ENABLED=true
      ;;
    --stream=false)
      STREAM_ENABLED=false
      ;;
    --stream=*)
      echo "Error: Invalid value for --stream. Use --stream=true or --stream=false." >&2
      exit 1
      ;;
    --model=*)
      MODEL="${1#*=}" # Extract value after "="
      ;;
    --api-endpoint=*)
      API_ENDPOINT="${1#*=}" # Extract value after "="
      ;;
    --help)
      usage
      ;;
    *)
      # Unknown argument, keep it for later processing if any
      ;;
  esac
  shift # Consume the argument
done

cat << EOF
{
  "model": "$MODEL",
  "api_endpoint": "$API_ENDPOINT",
  "stream_enabled": $STREAM_ENABLED,
  "config_dir": "$CONFIG_DIR",
  "token_file": "$TOKEN_FILE"
}
EOF
