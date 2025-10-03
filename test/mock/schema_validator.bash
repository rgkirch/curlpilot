#!/usr/bin/env bash
# This is a mock validator. It doesn't actually validate.
# It just checks if the input contains the word "invalid" to simulate a failure.

set -euo pipefail

#export PS4="+[$$] \${BASH_SOURCE##*/}:\${LINENO} "

schema_path="$1"
input_data=$(cat)

# A simple rule to simulate validation failure
if [[ "$input_data" == *"invalid"* ]]; then
  echo "Mock validator: Input contains the word 'invalid'. Failing." >&2
  exit 1
else
  echo "Mock validator: Success!" >&2
  exit 0
fi
