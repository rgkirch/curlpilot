# curlpilot/copilot/parse_response.bash
set -euo pipefail

cat | \
  grep -v '^data: \[DONE\]$' | \
  sed 's/^data: //' | \
  jq --unbuffered --raw-output --join-output \
    '.choices[0].delta.content // .choices[0].message.content // ""'
