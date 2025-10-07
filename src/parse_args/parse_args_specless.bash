# parse_args/parse_args_specless.bash
# Spec-less argument parser with strict rules.
# Rules:
#  Long options:
#    --key            => key: true
#    --key=value      => key: value (value may be empty and may start with '-')
#    --key value      => key: value (value must not start with '-')
#  Long key normalization: inner dashes converted to underscores for object keys.
#      e.g. --foo-bar => {"foo_bar": true}
#  Short option clusters (single dash):
#    -abc             => a: true, b: true, c: true (letters only)
#  Errors:
#    * Duplicate keys
#    * Short cluster containing non-letters (-ab1 or -9) => error
#    * Stray value without preceding key
#    * Missing value after --key when next token is absent
#  Separation vs equals: If value starts with '-', must use equals form.
#  Output: compact JSON {"key": value, ...} preserving insertion order (best effort)

set -euo pipefail

#set -x

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

trace "sourced deps"

_die() { echo "parse_args_specless error: $*" >&2; exit 1; }

# Validate long key characters (post normalization) strictly: [a-z0-9_]
_valid_long_key() {
  [[ "$1" =~ ^[a-z0-9_]+$ ]] || return 1
  return 0
}

# Lowercase + normalize dashes -> underscores
_normalize_long_key() {
  local raw="$1"
  raw=${raw,,}               # to lowercase
  raw=${raw//-/_}             # dashes to underscores
  echo "$raw"
}

# Data structures
declare -A KV
order=()
BOOL_SENTINEL="__BOOL_TRUE__"

args=("$@")
len=${#args[@]}
i=0

debug "args[*]=(${args[*]}) len=$len"

while (( i < len )); do
  trace "loop i=$i order_size=${#order[@]} order=(${order[*]})"
  tok="${args[$i]}"
  if [[ "$tok" == --* ]]; then
    trace "processing long opt token='$tok' i=$i"
    # Long option
    if [[ "$tok" == --*=* ]]; then
      trace "equals form detected token='$tok'"
      key_part=${tok%%=*}
      val_part=${tok#*=}
      key_name=${key_part#--}
      [[ -z "$key_name" ]] && _die "empty key in '$tok'"
      norm=$(_normalize_long_key "$key_name")
      _valid_long_key "$norm" || _die "invalid key characters in --$key_name (normalized '$norm')"
      [[ -v KV[$norm] ]] && _die "duplicate key: --$key_name"
      KV[$norm]="$val_part"
      order+=("$norm")
      ((++i))
      continue
    fi
    key_name=${tok#--}
    [[ -z "$key_name" ]] && _die "empty key in '$tok'"
    norm=$(_normalize_long_key "$key_name")
    _valid_long_key "$norm" || _die "invalid key characters in --$key_name (normalized '$norm')"
    [[ -v KV[$norm] ]] && _die "duplicate key: --$key_name"
    # Look ahead for value
    if (( i + 1 < len )); then
      trace "lookahead next='${args[$((i+1))]}' for key=$key_name"
      next="${args[$((i+1))]}"
      if [[ "$next" == -* ]]; then
        # Treat as boolean flag (user must use equals form for dash-leading value)
        KV[$norm]="$BOOL_SENTINEL"
        order+=("$norm")
        trace "added flag $norm; order=(${order[*]})"
        ((++i))
        continue
      else
        KV[$norm]="$next"
        order+=("$norm")
        i=$((i+2))
        continue
      fi
    else
      # terminal flag
      KV[$norm]="$BOOL_SENTINEL"
      order+=("$norm")
      ((++i))
      continue
    fi
  elif [[ "$tok" == -* ]]; then
    # Short cluster
    if [[ "$tok" == '-' ]]; then
      _die "lone '-' is invalid"
    fi
    cluster=${tok#-}
    [[ "$cluster" =~ ^[A-Za-z]+$ ]] || _die "invalid short option cluster contains non-letters: -$cluster"
    for ((ci=0; ci<${#cluster}; ci++)); do
      c=${cluster:$ci:1}
      lc=${c,,}
      [[ -v KV[$lc] ]] && _die "duplicate key: -$c"
      KV[$lc]="$BOOL_SENTINEL"
      order+=("$lc")
    done
    ((++i))
    continue
  else
    _die "stray value without key: '$tok'"
  fi
done

debug "loop done order_size=${#order[@]} order=(${order[*]})"

json='{}'
for k in "${order[@]}"; do
  v="${KV[$k]}"
  if [[ "$v" == "$BOOL_SENTINEL" ]]; then
    json=$(jq --arg k "$k" '. + {($k): true}' <<< "$json")
  else
    json=$(jq --arg k "$k" --arg v "$v" '. + {($k): $v}' <<< "$json")
  fi
done

debug "json $json"

echo "$json"
