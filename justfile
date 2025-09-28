help:
    @just --list

test *ARGS:
    @./run_tests.bash {{ARGS}}

copilot-review-diff:
    @./scripts/review.bash

tree:
    @tree --gitignore -a -I '.git|node_modules|bats|bats-assert|bats-file|bats-mock|bats-support|TickTick'
