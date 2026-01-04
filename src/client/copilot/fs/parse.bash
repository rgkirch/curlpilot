#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

register_dep parse_args "parse_args/parse_args.bash"

readonly ARG_SPEC_JSON='{
  "response": {
    "type": "string",
    "description": "The raw text response from the AI model."
  }
}'

main() {
  local job_ticket_json=$(jq -n \
    --argjson spec "$ARG_SPEC_JSON" \
    --compact-output \
    '{spec: $spec, args: $ARGS.positional}' \
    --args -- "$@")

  local parsed_args=$(exec_dep parse_args "$job_ticket_json")
  local response=$(jq --raw-output '.response' <<< "$parsed_args")

  # Use awk to parse the response and convert it to JSON
  echo "$response" | awk \
    ' \
    function flush_block() {
      if (path != "") {
        # Escape strings for JSON
        gsub(/\\/, "\\\\", original_block);
        gsub(/"/, "\\\"", original_block);
        gsub(/\n/, "\\n", original_block);
        gsub(/\r/, "\\r", original_block);
        gsub(/\t/, "\\t", original_block);

        gsub(/\\/, "\\\\", updated_block);
        gsub(/"/, "\\\"", updated_block);
        gsub(/\n/, "\\n", updated_block);
        gsub(/\r/, "\\r", updated_block);
        gsub(/\t/, "\\t", updated_block);

        if (blocks_json != "") {
          blocks_json = blocks_json ",";
        }
        blocks_json = blocks_json "{\"path\":\"" path "\",\"original\":\"" original_block "\",\"updated\":\"" updated_block "\"}";
      }
      path = "";
      state = "";
      original_block = "";
      updated_block = "";
    }

    /^<<<<<<< SEARCH$/ {
      state = "original";
      next;
    }

    /^=======$/ {
      state = "updated";
      next;
    }

    /^>>>>>>> REPLACE$/ {
      flush_block();
      next;
    }

    { 
      if (state == "original") {
        original_block = original_block $0 "\n";
      } else if (state == "updated") {
        updated_block = updated_block $0 "\n";
      } else if ($0 ~ /\S/) {
        flush_block();
        path = $0;
      }
    }

    END {
      flush_block();
      print "[" blocks_json "]";
    }
  '
}

main "$@"
