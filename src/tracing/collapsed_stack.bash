
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
    return 0
  fi
  declare -A name parent dur
  local f line id p n d
  for f in "${record_files[@]}"; do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
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
  # Aggregate durations by full path (root->leaf)
  declare -A agg
  local leaf cur component path_parts path i
  for leaf in "${!name[@]}"; do
    path_parts=()
    cur="$leaf"
    while [[ -n "$cur" ]]; do
      # Prefer recorded name; fallback to last id segment
      local label
      if [[ -v "name[$cur]" && -n "${name[$cur]}" ]]; then
        label="${name[$cur]}"
      else
        label="${cur##*/}"
      fi
      path_parts+=("$label")
      if [[ -v "parent[$cur]" && -n "${parent[$cur]}" ]]; then
        cur="${parent[$cur]}"
      else
        cur="" # reached root
      fi
    done
    local rev=()
    for (( i=${#path_parts[@]}-1; i>=0; i--)); do rev+=("${path_parts[$i]}"); done
    path="$(IFS=';'; echo "${rev[*]}")"
    if [[ -n "${dur[$leaf]:-}" ]]; then
      agg["$path"]=$(( ${agg[$path]:-0} + ${dur[$leaf]} ))
    fi
  done
  # Output aggregated collapsed stacks
  for path in "${!agg[@]}"; do
    printf '%s %s\n' "$path" "${agg[$path]}"
  done | sort
}

