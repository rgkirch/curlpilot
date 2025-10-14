set positional-arguments

mod schemas

# find . -type f -not -name .counter | sort | xargs head

help:
    @just --list

test *ARGS:
    @./run_tests.bash "$@"

test-all *ARGS:
    #!/bin/sh
    env CURLPILOT_LOG_LEVEL_BATS=FATAL ./run_tests.bash -r test --jobs 32 "$@"

copilot-review-diff:
    @./scripts/review.bash

tree:
    @tree --gitignore -a -I '.git|node_modules|bats|bats-assert|bats-file|bats-mock|bats-support|TickTick'

ai:
    @gemini-cli --include-directories /home/me/mirror/github.com/google-gemini/gemini-cli --include-directories /home/me/mirror/github.com/Aider-AI/aider


untested-src:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=()
    while IFS= read -r f; do
      base=$(basename "$f"); stem=${base%.*}
      if ! find test -type f -name "${stem}_test.bats" | grep -q .; then
        missing+=("$f")
      fi
    done < <(find src -type f \( -name '*.bash' -o -name '*.jq' -o -name '*.clj' \))
    if ((${#missing[@]})); then printf '%s\n' "${missing[@]}"; else echo "(all src files have matching *_test.bats)"; fi
