#!/bin/bash

set -euo pipefail

# curlpilot/scripts/diff_n_optimizer.sh

# Default values
TARGET_LINES_VAL=""
TARGET_TOKENS_VAL=""
MODE="tokens" # Default mode

# Function to validate if a value is a positive integer
validate_positive_integer() {
    local value="$1"
    local option_name="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo "Error: ${option_name} must be a positive integer." >&2
        exit 1
    fi
}

# Parse command-line arguments
TEMP=$(getopt -o '' --long target-lines:,target-tokens: -n 'diff_n_optimizer.sh' -- "$@")

if [ $? -ne 0 ]; then
    echo "Error: Failed to parse options." >&2
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        --target-lines)
            TARGET_LINES_VAL="$2"
            shift 2
            ;;
        --target-tokens)
            TARGET_TOKENS_VAL="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Internal error!" >&2
            exit 1
            ;;
    esac
done

# Validate and set target based on flags
if [[ -n "$TARGET_LINES_VAL" ]] && [[ -n "$TARGET_TOKENS_VAL" ]]; then
    echo "Error: Cannot specify both --target-lines and --target-tokens." >&2
    exit 1
elif [[ -n "$TARGET_LINES_VAL" ]]; then
    MODE="lines"
    TARGET_VAL="$TARGET_LINES_VAL"
    validate_positive_integer "$TARGET_VAL" "--target-lines"
elif [[ -n "$TARGET_TOKENS_VAL" ]]; then
    MODE="tokens"
    TARGET_VAL="$TARGET_TOKENS_VAL"
    validate_positive_integer "$TARGET_VAL" "--target-tokens"
else
    # Default to tokens if no flag is passed
    MODE="tokens"
    TARGET_VAL="2000" # Default token count
fi

# Calculate TARGET_THRESHOLD and echo initial targeting info
echo "Targeting ${MODE}: $TARGET_VAL" >&2

# Function to get diff count based on mode
get_diff_count() {
    local n="$1"
    if [[ "$MODE" == "lines" ]]; then
        git diff --unified="$n" --submodule=diff HEAD . 2>/dev/null | wc -l
    else # tokens mode
        # Calculate characters and then divide by 4 to get estimated tokens
        local char_count
        char_count=$(git diff --unified="$n" --submodule=diff HEAD . 2>/dev/null | wc -c)
        echo $((char_count / 4))
    fi
}

# --- Phase 1: Exponential Search for Upper Bound or Plateau ---
CURRENT_N=8
LAST_TESTED_N=0
LAST_TESTED_COUNT=-1

LOWER_BOUND_N_FOR_BISECTION=0
UPPER_BOUND_N_FOR_BISECTION=0

OPTIMAL_N_FINAL=0
MAX_COUNT_ACHIEVED_FINAL=0

SKIP_PHASE2=false

echo "Starting Phase 1: Exponential Search" >&2

while true; do
    # Ensure CURRENT_N is at least 0
    if [[ $CURRENT_N -lt 0 ]]; then
        CURRENT_N=0
    fi

    COUNT=$(get_diff_count "$CURRENT_N")
    echo "Phase 1: Testing N=${CURRENT_N}, ${MODE^}=${COUNT}" >&2

    # Condition 1: N exceeded the target
    if [[ $COUNT -gt $TARGET_VAL ]]; then
        UPPER_BOUND_N_FOR_BISECTION=$CURRENT_N
        LOWER_BOUND_N_FOR_BISECTION=$LAST_TESTED_N
        break # Exit Phase 1
    fi

    # Condition 2: Line count has plateaued (it didn't increase from the previous N)
    if [[ $LAST_TESTED_COUNT -ne -1 && $COUNT -eq $LAST_TESTED_COUNT ]]; then
        # Plateau detected.
        # If the plateaued count is less than TARGET_THRESHOLD, we have found our answer.
        if [[ $COUNT -lt $TARGET_VAL ]]; then
            OPTIMAL_N_FINAL=$LAST_TESTED_N
            MAX_COUNT_ACHIEVED_FINAL=$COUNT
            SKIP_PHASE2=true
            break # Exit Phase 1
        fi

        # If plateaued count is equal to TARGET_THRESHOLD, then LAST_TESTED_N is the answer.
        if [[ $COUNT -eq $TARGET_VAL ]]; then
            OPTIMAL_N_FINAL=$LAST_TESTED_N
            MAX_COUNT_ACHIEVED_FINAL=$COUNT
            SKIP_PHASE2=true
            break # Exit Phase 1
        fi

        # If plateaued count is still below TARGET_THRESHOLD but we need to find the largest N for it
        # (this case is handled by the bisection if we don't skip Phase 2)
        LOWER_BOUND_N_FOR_BISECTION=$LAST_TESTED_N
        UPPER_BOUND_N_FOR_BISECTION=$CURRENT_N
        break # Exit Phase 1
    fi

    # If neither condition met, continue doubling
    LAST_TESTED_N=$CURRENT_N
    LAST_TESTED_COUNT=$COUNT
    CURRENT_N=$((CURRENT_N * 2))

    # Safeguard for initial N=0 or very small N, or if N becomes too large
    if [[ $CURRENT_N -eq 0 ]]; then
        CURRENT_N=1
    fi
    # Arbitrary large cap if plateau not found and target not exceeded
    if [[ $CURRENT_N -gt 2000 ]]; then
        LOWER_BOUND_N_FOR_BISECTION=$LAST_TESTED_N
        UPPER_BOUND_N_FOR_BISECTION=2000
        break
    fi
done

echo "Phase 1 Complete." >&2

# --- Phase 2: Bisection within the found range (only if not skipped) ---
if ! $SKIP_PHASE2; then
    echo "Bisection range: [${LOWER_BOUND_N_FOR_BISECTION}, ${UPPER_BOUND_N_FOR_BISECTION}]" >&2
    LOW_N=$LOWER_BOUND_N_FOR_BISECTION
    HIGH_N=$UPPER_BOUND_N_FOR_BISECTION

    OPTIMAL_N_FINAL=$LOWER_BOUND_N_FOR_BISECTION # Initialize with the last known good N from Phase 1
    MAX_COUNT_ACHIEVED_FINAL=$(get_diff_count "$LOWER_BOUND_N_FOR_BISECTION")

    echo "Starting Phase 2: Bisection" >&2

    while [[ $LOW_N -le $HIGH_N ]]; do
        CURRENT_N=$(( (LOW_N + HIGH_N) / 2 ))

        # Ensure CURRENT_N is at least 0
        if [[ $CURRENT_N -lt 0 ]]; then
            CURRENT_N=0
        fi

        COUNT=$(get_diff_count "$CURRENT_N")
        echo "Phase 2: Testing N=${CURRENT_N}, ${MODE^}=${COUNT}" >&2

        if [[ $COUNT -le $TARGET_VAL ]]; then
            if [[ $COUNT -gt $MAX_COUNT_ACHIEVED_FINAL ]]; then
                MAX_COUNT_ACHIEVED_FINAL=$COUNT
                OPTIMAL_N_FINAL=$CURRENT_N
            fi
            LOW_N=$((CURRENT_N + 1))
        else
            HIGH_N=$((CURRENT_N - 1))
        fi
    done
fi

echo "--------------------------------------------------" >&2
echo "Optimal N found: ${OPTIMAL_N_FINAL}" >&2
echo "Resulting ${MODE}: ${MAX_COUNT_ACHIEVED_FINAL}" >&2
echo "Command: git diff --unified=${OPTIMAL_N_FINAL} --submodule=diff HEAD ." >&2

# Output only the optimal N to stdout for easy parsing
echo "${OPTIMAL_N_FINAL}"
