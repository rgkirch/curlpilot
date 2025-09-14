#!/bin/bash

set -euo pipefail

# curlpilot/scripts/install_openapi_spec.bash

# This script downloads the official OpenAI OpenAPI specification and replaces a
# number that is too large for standard 64-bit integer parsers (like yq's).
# This prevents parsing errors during validation or schema extraction.

# --- Configuration ---
# The official raw URL for the OpenAPI specification
URL="https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml"

# The local path where the file will be saved.
# You can change this or pass a path as the first argument to the script.
OUTPUT_PATH="${1:-./schemas/openapi.documented.yml}"

# The problematic number that causes parsers to fail.
BIG_NUMBER_TO_REPLACE="9223372036854776000"

# The largest possible 64-bit signed integer. This is a safe replacement.
REPLACEMENT_NUMBER="9223372036854775807"

# --- Tool Check ---
# Ensure curl and sed are available before starting.
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install it to continue." >&2
    exit 1
fi
if ! command -v sed &> /dev/null; then
    echo "Error: sed is not installed. Please install it to continue." >&2
    exit 1
fi

# --- Download Step ---
if [[ -f "$OUTPUT_PATH" ]]; then
    echo "👍 OpenAPI spec already exists at $OUTPUT_PATH. Skipping download."
else
    echo "⬇️  Downloading the latest OpenAPI spec from:"
    echo "   $URL"
    if curl -L -sS -o "$OUTPUT_PATH" "$URL"; then
        echo "✅ Download successful. File saved to: $OUTPUT_PATH"
    else
        echo "❌ Download failed. Please check the URL and your network connection." >&2
        exit 1
    fi
fi

# --- Replacement Step ---
echo ""
echo "🔄 Checking for the oversized number..."

# -q (quiet) flag makes grep exit successfully as soon as it finds a match.
if grep -q "$BIG_NUMBER_TO_REPLACE" "$OUTPUT_PATH"; then
    echo "   Found the number $BIG_NUMBER_TO_REPLACE. Replacing it now..."
    # Use sed for in-place replacement. Double quotes are used to allow
    # variable expansion for the numbers.
    sed -i "s/$BIG_NUMBER_TO_REPLACE/$REPLACEMENT_NUMBER/g" "$OUTPUT_PATH"
    echo "✅ Replacement successful."
else
    echo "👍 The oversized number was not found in the file. No changes needed."
fi

echo ""
echo "🎉 Process complete. The spec file is ready to be used."
