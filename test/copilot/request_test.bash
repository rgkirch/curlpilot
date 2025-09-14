#!/bin/bash
set -euo pipefail

# PURPOSE: Verify that request.bash calls curl with the correct arguments.
# This test must be run from the project's root directory.

echo "🧪 Running unit test for copilot/request.bash..."

# --- Test Setup ---
source "$(dirname "$0")/../../deps.bash"
register_dep request copilot/request.bash

# 1. Define the mock curl function to capture arguments
curl() {
  echo "--- Mock curl received these arguments: ---"
  printf "  -> %s\n" "$@"
  echo "-----------------------------------------"
}
export -f curl

# 2. Use the simple 'success' mock for the auth dependency
export CPO_COPILOT__AUTH_SH="test/mocks/scripts/success/auth.bash"

# 3. Set environment variables for the script under test
export API_ENDPOINT="http://test.api/chat"
export COPILOT_SESSION_TOKEN="unit-test-fake-token"


# --- Run the Test ---
echo '{"prompt": "hello"}' | exec_dep request

echo "✅ Unit test completed."
