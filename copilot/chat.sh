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
register copilot_request "copilot/make_request.sh"
register parse_args "copilot/parse_chat_args.sh"

# --- Modified Pipeline with Error Handling ---

# This command captures both the response body and the HTTP status code.
# The status code is appended to the output on a new line, thanks to -w "\n%{http_code}".
# The -f flag is removed to ensure we receive the body even on error.
#
# The -s flag in jq stands for --slurp. It changes how jq reads its input.
# Instead of processing each JSON object from the input stream one at a time,
# the -s flag tells jq to read the entire stream of objects into a single large
# array. It then runs your filter just once on that complete array.
#
# echo '{"role": "user", "content": "hi"}' | ./copilot/chat.sh
# Sending request to Copilot...
# Hello! How can I help you today? 😊

OPTIONS="$(exec_dep parse_args "$@")"

REQUEST="$(jq '{
  model,
  "stream": .stream_enabled
}' <<<"$OPTIONS")"

REQUEST="$(jq \
  --slurp \
  --argjson request "$REQUEST" \
  '$request + {"messages": .}')"

STREAM_ENABLED="$(jq '.stream_enabled' <<<"$OPTIONS")"

# Pipe the request to the subshell for processing
exec_dep copilot_request <<<"$REQUEST" | {
  set -euo pipefail

  # Use read to split the stream on the null delimiter
  IFS= read -r -d $'\0' response_body
  read -r status_json_part || [[ -n "$response_body" ]]

  # Extract values from the status JSON
  http_code=$(echo "$status_json_part" | jq -r '.http_code')
  exitcode=$(echo "$status_json_part" | jq -r '.exitcode')

  # Check for curl errors
  if [[ "$exitcode" -ne 0 ]]; then
      errormsg=$(echo "$status_json_part" | jq -r '.errormsg')
      echo "Error: curl command failed with exit code ${exitcode}. Message: ${errormsg}" >&2
      exit 1
  fi

  # Check for HTTP errors
  if [[ "$http_code" -ge 400 ]]; then
    echo "Error: Request failed with HTTP status ${http_code}" >&2
    echo "Server response:" >&2
    # Pretty-print the JSON error message if possible, otherwise print as is
    if echo "$response_body" | jq . >/dev/null 2>&1; then
        echo "$response_body" | jq . >&2
    else
        echo "$response_body" >&2
    fi
    exit 1
  fi

  # If the request was successful, process the response body.
  # The unified jq filter handles both streaming and non-streaming responses.
  echo "$response_body" | \
    grep -v '^data: \[DONE\]$' | \
    sed 's/^data: //' | \
    jq -j -n 'inputs | .choices[0] | .delta.content // .message.content'
}

echo
