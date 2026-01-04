#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"

readonly ARG_SPEC_JSON='{
  "request": {
    "type": "string",
    "description": "The user's request for changes."
  },
  "files": {
    "type": "json",
    "description": "A JSON array of objects, where each object has a `path` and `content` key."
  }
}'

main() {
  local job_ticket_json=$(jq -n \
    --argjson spec "$ARG_SPEC_JSON" \
    --compact-output \
    '{spec: $spec, args: $ARGS.positional}' \
    --args -- "$@")

  local parsed_args=$(exec_dep parse_args "$job_ticket_json")
  local request=$(jq --raw-output '.request' <<< "$parsed_args")
  local files_json=$(jq --compact-output '.files' <<< "$parsed_args")

  local file_content_prompt=""
  for row in $(echo "${files_json}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }
   
    local path=$(_jq '.path')
    local content=$(_jq '.content')

    file_content_prompt+="Here is the content of '$path':\n\
\
${content}\n\
\
\n"
  done

  cat <<EOF
Act as an expert software developer.
You are asked to perform the following task: ${request}.

${file_content_prompt}When you have the answer, please reply with the changes using one or more SEARCH/REPLACE blocks.

All changes to files must use this SEARCH/REPLACE block format:

path/to/filename.ext
<<<<<<< SEARCH
... original lines to be replaced ...
=======
... new lines to insert ...
>>>>>>> REPLACE

- The SEARCH block must exactly match the original file content.
- To create a new file, use a new file path and leave the SEARCH block empty.
- Only output SEARCH/REPLACE blocks. Do not include any other text in your response.
EOF
}

main "$@"
