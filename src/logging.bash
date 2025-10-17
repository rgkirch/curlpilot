#!/usr/bin/bash
# Provides intelligent logging functions with multiple levels and dual output.

# Include guard
if [[ -n "${_LOGGING_BASH_SOURCED:-}" ]]; then
  return 0
fi
readonly _LOGGING_BASH_SOURCED=1


# --- Configuration ---

# Define standard log levels as numeric values for comparison.
readonly LOG_LEVEL_FATAL=0
readonly LOG_LEVEL_ERROR=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_INFO=3
readonly LOG_LEVEL_DEBUG=4
readonly LOG_LEVEL_TRACE=5

# Helper function to convert a log level name to its numeric value.
_get_level_num() {
    case "${1:-INFO}" in
        FATAL) echo $LOG_LEVEL_FATAL ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        TRACE) echo $LOG_LEVEL_TRACE ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# --- Main Logic ---

# Internal logging function that all public functions call.
_log() {
  local level_num=$1
  local level_name=$2
  shift 2

  local cfg_lvl_bats=$(_get_level_num "${CURLPILOT_LOG_LEVEL_BATS:-INFO}")
  if (( level_num <= cfg_lvl_bats )); then
    if : >&3 2>/dev/null; then
      local message
      message="$(date '+%T.%N') [BATS:$(basename "${BASH_SOURCE[2]:-$0}")] $level_name: $*"
      echo "$message" >&3
    fi
  fi
  local configured_level=$(_get_level_num "${CURLPILOT_LOG_LEVEL:-INFO}")
  if (( level_num <= configured_level )); then
    local message
    # BASH_SOURCE[2] is used because the call stack is e.g. log_info() -> _log().
    message="$(date '+%T.%N') [$(basename "${BASH_SOURCE[2]:-$0}")] $level_name: $*"
    echo "$message" >&2
  fi
}

# Public logging functions for each level.
log_fatal() { _log $LOG_LEVEL_FATAL "FATAL" "$@"; }
log_error() { _log $LOG_LEVEL_ERROR "ERROR" "$@"; }
log_warn()  { _log $LOG_LEVEL_WARN  "WARN"  "$@"; }
log_info()  { _log $LOG_LEVEL_INFO  "INFO"  "$@"; }
log_debug() { _log $LOG_LEVEL_DEBUG "DEBUG" "$@"; }
log_trace() { _log $LOG_LEVEL_TRACE "TRACE" "$@"; }
