#!/bin/bash
#
# Smart Profiler v18 - `set -u` safe, robust delimiters, and now
#                      respects a pre-set PROFILE_LOG_DIR from a parent script.
#

# ---
# CASE 1: The guard is NOT set.
# This means this is the *first time* we're being sourced.
# Our job is to "arm" the profiler.
# ---
if [[ -z "${_BASH_PROFILER_ACTIVE:-}" ]]; then

    # 1. Arm the profiler by setting the guard.
    export _BASH_PROFILER_ACTIVE=1

    # 2. Find the full, real path to this script.
    profiler_path="$(realpath "${BASH_SOURCE[0]}")"

    # 3. Set BASH_ENV so all child scripts will be profiled.
    export BASH_ENV="$profiler_path"

    # 4. FIX: Use the existing PROFILE_LOG_DIR if it's set by the parent,
    #    otherwise create a default one.
    : "${PROFILE_LOG_DIR:=/tmp/profile-logs.${$}}"
    export PROFILE_LOG_DIR
    mkdir -p "$PROFILE_LOG_DIR"

    echo "Bash Profiler: ON" >&2

    # 5. Define a simple 'off' function for convenience.
    profile_off() {
        unset BASH_ENV
        unset _BASH_PROFILER_ACTIVE
        unset PROFILE_LOG_DIR
        echo "Bash Profiler: OFF" >&2
        unset -f profile_off
    }

# ---
# CASE 2: The guard IS set.
# This means BASH_ENV is executing this script to
# profile a *target script*.
# ---
else

    # 1. Use the exported log dir, with a fallback to /tmp.
    _PROFILE_LOG="${PROFILE_LOG_DIR:-/tmp}/${$}.$(basename "$0").profile.log"

    # 2. DYNAMICALLY find an open FD and assign it to _PROFILE_FD.
    exec {_PROFILE_FD}> "$_PROFILE_LOG"

    # 3. Tell Bash to send all trace output to that dynamic FD.
    export BASH_XTRACEFD=$_PROFILE_FD

    # 4. Define the delimiters in variables first.
    _PROF_RS=$'\x1E' # Record Separator
    _PROF_US=$'\x1F' # Unit Separator

    # 5. Set the final, robust PS4.
    export PS4="+ ${_PROF_US}${EPOCHREALTIME}${_PROF_US}${PPID}${_PROF_US}${BASH_SUBSHELL}${_PROF_US}${BASH_SOURCE[0]}${_PROF_US}${LINENO}${_PROF_US}${FUNCNAME[@]}${_PROF_US}${_PROF_RS} "

    # 6. Announce that profiling is active (to stderr).
    # echo "PROFILING: Enabled for PID $$. Log file: $_PROFILE_LOG" >&2

    # 7. Finally, turn on tracing!
    set -x
fi
