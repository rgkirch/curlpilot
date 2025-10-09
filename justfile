set positional-arguments

mod schemas

# find . -type f -not -name .counter | sort | xargs head

help:
    @just --list

test *ARGS:
    @./run_tests.bash "$@"

test-all *ARGS:
    @./run_tests.bash -r test --jobs 32 "$@"

copilot-review-diff:
    @./scripts/review.bash

tree:
    @tree --gitignore -a -I '.git|node_modules|bats|bats-assert|bats-file|bats-mock|bats-support|TickTick'

ai:
    @gemini-cli --include-directories /home/me/mirror/github.com/google-gemini/gemini-cli --include-directories /home/me/mirror/github.com/Aider-AI/aider
