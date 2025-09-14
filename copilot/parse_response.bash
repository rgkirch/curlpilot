#!/bin/bash

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

# curlpilot/copilot/parse_response.bash

# Use read to split the stream on the null delimiter
IFS= read -r -d $'' response_body
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
  sed 's/^data: //'
  jq -j -n 'inputs | .choices[0] | .delta.content // .message.content'
