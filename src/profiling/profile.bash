#!/bin/bash
#
# Smart Profiler v4 - No EXIT trap
#
# Uses a guard variable (_BASH_PROFILER_ACTIVE) to know *why* it's running.
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

    echo "Bash Profiler: ON" >&2
    echo "All subsequent Bash scripts will be profiled." >&2

    # 4. Define a simple 'off' function for convenience.
    profile_off() {
        unset BASH_ENV
        unset _BASH_PROFILER_ACTIVE
        echo "Bash Profiler: OFF" >&2
        unset -f profile_off
    }

# ---
# CASE 2: The guard IS set.
# This means BASH_ENV is executing this script to
# profile a *target script*.
# ---
else

    # 1. Set a unique log file path (using script name and PID).
    _PROFILE_LOG="/tmp/$(basename "$0").${$}.profile.log"

    # 2. DYNAMICALLY find an open FD and assign it to _PROFILE_FD.
    #    The OS will close this when the script exits.
    exec {_PROFILE_FD}> "$_PROFILE_LOG"

    # 3. Tell Bash to send all trace output to that dynamic FD.
    export BASH_XTRACEFD=$_PROFILE_FD

    # 4. Set our detailed PS4 for logging.
    export PS4='[${EPOCHREALTIME}] [${BASH_SOURCE[0]}:${LINENO}] [${FUNCNAME[@]}] '

    # 5. Announce that profiling is active (to stderr).
    echo "PROFILING: Enabled for PID $$. Log file: $_PROFILE_LOG" >&2

    # 6. Finally, turn on tracing!
    set -x
fi
