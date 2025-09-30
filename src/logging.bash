# logging.bash
# scripts intended to be sourced should not change the environment of the caller. so, don't set -euox pipefail

# Centralized logging function for curlpilot scripts.
#
# Usage:
#   log "My log message"
#
# Behavior is controlled by the CURLPILOT_LOG_TARGET environment variable:
# - If CURLPILOT_LOG_TARGET is "2", logs are sent to stderr.
# - If CURLPILOT_LOG_TARGET is "3", logs are sent to file descriptor 3.
# - If unset or any other value, logging is disabled.

log() {
  # Do nothing if logging is not configured.
  if [[ -z "${CURLPILOT_LOG_TARGET:-}" ]]; then
    return 0
  fi

  local message
  # BASH_SOURCE[1] gives the path to the caller's script.
  message="$(date '+%T.%N') [$(basename "${BASH_SOURCE[1]}")] $*"

  # Determine the log target and write the message.
  case "${CURLPILOT_LOG_TARGET}" in
    2)
      echo "$message" >&2
      ;;
    3)
      echo "$message" >&3
      ;;
    *)
      # Invalid or disabled target, so do nothing.
      return 0
      ;;
  esac
}
