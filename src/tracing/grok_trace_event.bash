#!/usr/bin/env bash

# Function to generate trace event format from trace root
# Usage: grok_trace_event_from_trace_root <trace_root> <mode>
# mode: wall or cpu
grok_trace_event_from_trace_root() {
  local trace_root="$1"
  local mode="$2"

  # Ensure jq is available
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required to parse JSON." >&2
    return 1
  fi

  # Find all record.ndjson files
  local files
  files=$(find "$trace_root" -type f -name record.ndjson 2>/dev/null | sort)

  # Associative arrays
  declare -A id_to_name
  declare -A id_to_parent
  declare -A id_to_duration
  declare -A id_to_start
  declare -A id_to_pid
  declare -A id_to_args

  # Collect data from files
  local original_ids=()
  for file in $files; do
    if [[ ! -s "$file" ]]; then continue; fi
    local json
    json=$(cat "$file")
    local id
    id=$(echo "$json" | jq -r '.id // empty')
    if [[ -z "$id" ]]; then continue; fi
    local name
    name=$(echo "$json" | jq -r '.name // empty')
    local parentId
    parentId=$(echo "$json" | jq -r '.parentId // empty')
    local start
    start=$(echo "$json" | jq -r '.data.start_timestamp_us // empty')
    local wall
    wall=$(echo "$json" | jq -r '.data.wall_duration_us // "0"')
    local cpu
    cpu=$(echo "$json" | jq -r '.data.cpu_duration_us // "0"')
    local pid
    pid=$(echo "$json" | jq -r '.pid // empty')
    local args
    args=$(echo "$json" | jq -c '.data // {}')

    id_to_name["$id"]="$name"
    id_to_parent["$id"]="$parentId"
    id_to_start["$id"]="$start"
    id_to_pid["$id"]="$pid"
    id_to_args["$id"]="$args"
    if [[ "$mode" == "wall" ]]; then
      id_to_duration["$id"]="$wall"
    else
      id_to_duration["$id"]="$cpu"
    fi
    original_ids+=("$id")
  done

  # Infer missing parents
  for cid in "${original_ids[@]}"; do
    local pid="${id_to_parent[$cid]}"
    while [[ -n "$pid" && ! "${id_to_name[$pid]+exists}" ]]; do
      local inferred_name="${pid##*/}"
      id_to_name["$pid"]="$inferred_name"
      local ppid="${pid%/*}"
      if [[ "$ppid" == "$pid" ]]; then
        ppid=""
      fi
      id_to_parent["$pid"]="$ppid"
      pid="$ppid"
    done
  done

  # Function to get stack string
  get_stack() {
    local cid="$1"
    local stack=()
    while [[ -n "$cid" ]]; do
      stack=("${id_to_name[$cid]}" "${stack[@]}")
      cid="${id_to_parent[$cid]}"
    done
    local IFS=';'
    echo "${stack[*]}"
  }

  # Output for each original span with duration as ndjson lines
  for id in "${original_ids[@]}"; do
    local dur="${id_to_duration[$id]}"
    local start="${id_to_start[$id]}"
    local pid="${id_to_pid[$id]}"
    local args="${id_to_args[$id]}"
    if [[ "$dur" == "0" || "$dur" == "null" || -z "$dur" || -z "$start" || "$start" == "null" || -z "$pid" ]]; then
      continue
    fi
    local stack
    stack=$(get_stack "$id")
    local name="${stack//;/ > }"
    echo "{\"name\":\"$name\",\"cat\":\"test\",\"ph\":\"X\",\"ts\":$start,\"dur\":$dur,\"pid\":$pid,\"tid\":0,\"args\":$args}"
  done | jq -s '{traceEvents: .}'
}
