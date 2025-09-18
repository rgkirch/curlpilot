# test/mocks/scripts/success/auth.bash
set -euo pipefail
token="${COPILOT_SESSION_TOKEN:-mock_token}"
echo "{\"session_token\": \"$token\"}"
