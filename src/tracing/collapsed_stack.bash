
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
  # Emit one line per record (preserve ordinal components to distinguish repeats)
  local id path duration path_segments seg root_name
  for id in "${!name[@]}"; do
    duration="${dur[$id]:-0}"
    # Build path from id segments
    IFS='/' read -r -a path_segments <<< "$id"
    # Replace first segment (suite id) with suite record name if available
    root_name="${name["${path_segments[0]}"]:-${path_segments[0]}}"
    path_segments[0]="$root_name"
    # For leaf segment use original segment (with ordinal) rather than plain name to disambiguate
    # If segment has ordinal (NN_) keep it; else optionally append name
    # Already contained in id
    path="$(IFS=';'; echo "${path_segments[*]}")"
    printf '%s %s\n' "$path" "$duration"
  done
}

