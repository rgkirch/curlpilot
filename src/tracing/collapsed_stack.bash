
#!/usr/bin/env bash
# Generate collapsed stack format from trace tree produced by deps.bash
# Usage: collapsed_stack_from_trace_root TRACE_ROOT [metric]
# metric: cpu (default) | wall
collapsed_stack_from_trace_root() {
  local trace_root="$1" metric="${2:-cpu}" record_files
  if [[ -z "$trace_root" || ! -d "$trace_root" ]]; then
    echo "ERROR: trace root dir required" >&2; return 1
  fi
  shopt -s nullglob
  mapfile -t record_files < <(find "$trace_root" -type f -name record.ndjson)
  if (( ${#record_files[@]} == 0 )); then
    echo ""; return 0
  fi
  declare -A name parent dur
  local f id p n d key_field
  for f in "${record_files[@]}"; do
    # Extract fields
    while IFS= read -r line; do
      id=$(jq -r '.id' <<<"$line")
      p=$(jq -r '.parentId' <<<"$line")
      n=$(jq -r '.name' <<<"$line")
      if [[ "$metric" == "wall" ]]; then
        d=$(jq -r '.data.wall_duration_us // 0' <<<"$line")
      else
        d=$(jq -r '.data.cpu_duration_us // .data.wall_duration_us // 0' <<<"$line")
      fi
      name["$id"]="$n"
      parent["$id"]="$p"
      dur["$id"]="$d"
    done < "$f"
  done
  # Identify leaves (ids that are not parents of others)
  declare -A is_parent
  for id in "${!parent[@]}"; do
    p="${parent[$id]}"
    [[ -n "$p" ]] && is_parent["$p"]=1
  done
  local leaf stack cur
  for leaf in "${!name[@]}"; do
    if [[ -v "is_parent[$leaf]" ]]; then
      continue
    fi
    stack=()
    cur="$leaf"
    # Build path upwards (robust against missing parent/name entries)
    while [[ -n "$cur" ]]; do
      if [[ -v "name[$cur]" ]]; then
        stack+=("${name[$cur]}")
      fi
      if [[ -v "parent[$cur]" ]]; then
        cur="${parent[$cur]}"
      else
        break
      fi
    done
    # Reverse stack
    local i rev=()
    for (( i=${#stack[@]}-1; i>=0; i--)); do rev+=("${stack[$i]}"); done
    printf '%s %s\n' "$(IFS=';'; echo "${rev[*]}")" "${dur[$leaf]}"
  done
}

