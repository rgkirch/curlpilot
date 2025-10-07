# logging.bash
# Provides intelligent logging functions with multiple levels.


if [[ -n "${_LOGGING_BASH_SOURCED:-}" ]]; then
  return 0
fi
readonly _LOGGING_BASH_SOURCED=1

# Determine the log target file descriptor automatically.
# If a Bats test variable is set, log to fd 3, otherwise log to stderr (fd 2).
LOG_FD=2
if [[ -n "${BATS_TEST_FILENAME:-}" ]]; then
  LOG_FD=3
fi

# Define standard log levels as numeric values for comparison.
LOG_LEVEL_FATAL=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4
LOG_LEVEL_TRACE=5

# Read the configured log level from the environment. Default to INFO.
# Convert the string level (e.g., "INFO") to its numeric value.
case "${CURLPILOT_LOG_LEVEL:-INFO}" in
  FATAL) configured_level=$LOG_LEVEL_FATAL ;;
  ERROR) configured_level=$LOG_LEVEL_ERROR ;;
  WARN)  configured_level=$LOG_LEVEL_WARN ;;
  INFO)  configured_level=$LOG_LEVEL_INFO ;;
  DEBUG) configured_level=$LOG_LEVEL_DEBUG ;;
  TRACE) configured_level=$LOG_LEVEL_TRACE ;;
  *)     configured_level=$LOG_LEVEL_INFO ;;
esac

# Internal logging function that all public functions call.
_log() {
  local level_num=$1
  local level_name=$2
  shift 2
  
  # Only log if the message's level is at or above the configured level.
  if (( level_num <= configured_level )); then
    local message
    message="$(date '+%T.%N') [$(basename "${BASH_SOURCE[2]:-$0}")] $level_name: $*"
    echo "$message" >&"$LOG_FD"
  fi
}

# Public logging functions for each level.
log_fatal() { _log $LOG_LEVEL_FATAL "FATAL" "$@"; }
log_error() { _log $LOG_LEVEL_ERROR "ERROR" "$@"; }
log_warn()  { _log $LOG_LEVEL_WARN  "WARN"  "$@"; }
log_info()  { _log $LOG_LEVEL_INFO  "INFO"  "$@"; }
log_debug() { _log $LOG_LEVEL_DEBUG "DEBUG" "$@"; }
log_trace() { _log $LOG_LEVEL_TRACE "TRACE" "$@"; }
