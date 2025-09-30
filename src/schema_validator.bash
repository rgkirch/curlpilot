# schema_validator.bash
set -euo pipefail

# 1. Source the framework to get the resolve_path function.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.deps.bash"

# 2. Use resolve_path to get the absolute path to the Node.js script.
NODE_VALIDATOR_PATH=$(resolve_path "ajv/validate.js")

# --- Main Logic ---

# Check that the node script actually exists before trying to run it.
if [[ ! -f "$NODE_VALIDATOR_PATH" ]]; then
    echo "Error: The node validator script could not be found at '$NODE_VALIDATOR_PATH'" >&2
    exit 1
fi

# Ensure a schema path was provided as an argument.
if [[ -z "${1-}" ]]; then
  echo "Usage: cat data.json | $0 <path_to_schema.json>" >&2
  exit 1
fi
schema_path="$1"

# Read all of stdin into a variable.
input=$(cat)

# Provide a clear error if stdin was empty.
if [[ -z "$input" ]]; then
    echo "Error: Standard input was empty, which is not valid JSON." >&2
    exit 1
fi

# Execute the Node.js validator directly with the correct path.
exec node "$NODE_VALIDATOR_PATH" "$schema_path" <(echo "$input")
