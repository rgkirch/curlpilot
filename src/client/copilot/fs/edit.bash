#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep fs_prompt "client/copilot/fs/prompt.bash"
register_dep fs_parse "client/copilot/fs/parse.bash"
register_dep fs_apply "client/copilot/fs/apply.bash"
register_dep parse_args "parse_args/parse_args.bash"
register_dep copilot_chat "client/copilot/chat.bash"

readonly ARG_SPEC_JSON='{
  "request": {
    "type": "string",
    "description": "The user's request for changes."
  },
  "files": {
    "type": "string[]",
    "description": "An array of absolute file paths to be edited."
  },
  "verbose": {
    "name": "verbose",
    "type": "bool",
    "help": "Enable verbose output.",
    "default": false
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
  
  # 1. Read file contents
  local file_contents_json=$(jq -n '[]')
  for file_path in $(jq --raw-output '.[]' <<< "$files_json"); do
    local content=$(cat "$file_path")
    file_contents_json=$(echo "$file_contents_json" | jq --arg path "$file_path" --arg content "$content" '. + [{path: $path, content: $content}]')
  done

  # 2. Construct the prompt
  local prompt_ticket_json=$(jq -n \
    --arg request "$request" \
    --argjson files "$file_contents_json" \
    '{request: $request, files: $files}')
  local prompt=$(exec_dep fs_prompt "$prompt_ticket_json")

  # 3. Send prompt to AI (using a placeholder for now)
  # In a real scenario, this would call the actual AI client
  local ai_response=$(exec_dep copilot_chat "$prompt")

  # 4. Parse the AI response
  local parse_ticket_json=$(jq -n --arg response "$ai_response" '{response: $response}')
  local edits_json=$(exec_dep fs_parse "$parse_ticket_json")

  # 5. Apply the edits
  local apply_ticket_json=$(jq -n --argjson edits "$edits_json" '{edits: $edits}')
  exec_dep fs_apply "$apply_ticket_json"
}

main "$@"
