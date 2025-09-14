#!/bin/bash
set -euo pipefail

# curlpilot/scripts/review.bash

PEER_MD_CONTENT=$(cat PEER.md 2>/dev/null || true)
OPTIMAL_N=$(scripts/diff_n_optimizer.bash --target-tokens=2000 2>/dev/null || echo 10)

# Read additional prompt from stdin
ADDITIONAL_PROMPT=$(cat)

# Combine PEER.md content, git diff, and additional prompt
INPUT_CONTENT=$(cat <<EOF
${PEER_MD_CONTENT}

$(git diff --unified="${OPTIMAL_N}" --submodule=diff HEAD .)

${ADDITIONAL_PROMPT}
EOF
)

jq -n --arg content "$INPUT_CONTENT" '[{"role": "user", "content": $content}]' | copilot/chat.bash --stream=false
