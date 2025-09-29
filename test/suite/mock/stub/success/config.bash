# test/mocks/scripts/success/config.bash
set -euo pipefail

jq --null-input \
  --arg api_endpoint "$API_ENDPOINT" \
  '{
    copilot: { api_endpoint: $api_endpoint },
    gemini: { api_endpoint: $api_endpoint }
  }'
