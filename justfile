help:
    @just --list

test *ARGS:
    @./run_tests.bash {{ARGS}}

test-all:
    @./run_tests.bash just test -r test/suite --jobs 32

copilot-review-diff:
    @./scripts/review.bash

tree:
    @tree --gitignore -a -I '.git|node_modules|bats|bats-assert|bats-file|bats-mock|bats-support|TickTick'
