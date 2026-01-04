#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"

readonly ARG_SPEC_JSON='{
  "edits": {
    "type": "json",
    "description": "A JSON array of edit objects, each with `path`, `original`, and `updated` keys."
  }
}'

main() {
  local job_ticket_json=$(jq -n \
    --argjson spec "$ARG_SPEC_JSON" \
    --compact-output \
    '{spec: $spec, args: $ARGS.positional}' \
    --args -- "$@")

  local parsed_args=$(exec_dep parse_args "$job_ticket_json")
  local edits_json=$(jq --compact-output '.edits' <<< "$parsed_args")

  for row in $(echo "${edits_json}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }

    local path=$(_jq '.path')
    local original=$(_jq '.original')
    local updated=$(_jq '.updated')

    # Create the file if it doesn't exist and the original block is empty
    if [[ ! -f "$path" ]] && [[ -z "$original" ]]; then
      touch "$path"
    fi

    # Check if the file exists
    if [[ ! -f "$path" ]]; then
      echo "Error: File not found at ${path}" >&2
      continue
    fi

    # Use a temporary file for sed to handle in-place editing safely
    local tmp_file=$(mktemp)

    # Create the sed script
    # The script finds the start of the block, then tries to match the whole block.
    # This is a simplified approach. A more robust solution might use a different tool
    # or a more complex script to handle edge cases like partial matches.
    if [[ -z "$original" ]]; then
        # If original is empty, append the updated content to the end of the file.
        cat "$path" > "$tmp_file"
        echo -e "$updated" >> "$tmp_file"
    else
        # Prepare content for sed by escaping special characters
        local original_escaped=$(echo -n "$original" | sed -e 's/[\\/&]/\\&/g')
        local updated_escaped=$(echo -n "$updated" | sed -e 's/[\\/&]/\\&/g')

        # Read the file content and the original content into variables
        file_content=$(cat "$path")
        
        # Use Python for robust multi-line search and replace
        python3 -c 'import sys; file_content=sys.stdin.read(); new_content=file_content.replace(sys.argv[1], sys.argv[2]); sys.stdout.write(new_content)' "$original" "$updated" < "$path" > "$tmp_file"

        # Check if the replacement was successful
        if cmp -s "$path" "$tmp_file"; then
            echo "Warning: Search block not found in ${path}. No changes made to this file." >&2
            rm "$tmp_file"
            continue
        fi
    fi

    # Replace the original file with the modified temporary file
    mv "$tmp_file" "$path"

    echo "Applied edit to ${path}"
  done
}

main "$@"
