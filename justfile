help:
    @just --list

test:
    @./run_tests.bash

copilot-review-diff:
    @./scripts/review.bash

tree:
    @tree -a -I '.git|node_modules|bats|bats-assert|bats-file|bats-mock|bats-support'
