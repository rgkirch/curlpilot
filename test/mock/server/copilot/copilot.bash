# test/mock/server/copilot.bash
set -euo pipefail

# ---
# Starts a mock nc server in the background to serve a static response.
#
# Usage:
#   mock_server.bash <path_to_response_generator> [args_for_generator...]
#
# Outputs two lines for the calling test script to capture:
#   1. The random port number the server is listening on.
#   2. The Process ID (PID) of the background nc server for cleanup.
# ---

# The first argument is the script that will generate the HTTP response.
RESPONSE_GENERATOR_SCRIPT="$1"
shift

if [[ ! -x "$RESPONSE_GENERATOR_SCRIPT" ]]; then
  echo "Error: Response generator script not found or not executable: $RESPONSE_GENERATOR_SCRIPT" >&2
  exit 1
fi

# Find a random, available port to avoid conflicts in parallel tests.
PORT=$(shuf -i 20000-65000 -n 1)

# Start nc in the background. It will serve the HTTP headers and then execute
# the response generator script to create the body.
(
  (
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
    "$RESPONSE_GENERATOR_SCRIPT" "$@"
  ) | nc -l "$PORT"
) &
NC_PID=$!

# Output the port and PID so the test script can use them.
echo "$PORT"
echo "$NC_PID"
