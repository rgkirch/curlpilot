# schema_validator.bash
set -euo pipefail

# A wrapper to use the Node.js ajv validator. It reads data from stdin
# and uses process substitution to pass it as a file path to the Node script.
#
# Usage:
#   cat data.json | ./schema_validator.bash schema.json
#

# --- Configuration ---
# This script assumes your validate.js is in a sibling directory named 'ajv'.
# Adjust this path if your directory structure is different.
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
NODE_VALIDATOR_PATH="$SCRIPT_DIR/ajv/validate.js"
# ---------------------

# 1. Ensure a schema path was provided as an argument.
if [[ -z "${1-}" ]]; then
  echo "Usage: cat data.json | $0 <path_to_schema.json>" >&2
  exit 1
fi
schema_path="$1"

# 2. Read all of stdin into a variable.
# This allows us to check if it's empty before proceeding.
input=$(cat)

# 3. Provide a clear error if stdin was empty, which is not valid JSON.
if [[ -z "$input" ]]; then
    echo "Error: Standard input was empty, which is not valid JSON." >&2
    exit 1
fi

# 4. Execute the Node.js validator.
# Process substitution <(echo "$input") runs `echo` and provides its
# output as a temporary file path that the Node script can read.
node "$NODE_VALIDATOR_PATH" "$schema_path" <(echo "$input")
