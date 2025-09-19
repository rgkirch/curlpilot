
# Bats (Bash Automated Testing System)

This document provides a comprehensive overview of Bats, the Bash Automated Testing System. It covers installation, test creation, command-line usage, and common practices.

## Installation

The recommended way to include Bats in your project is as a Git submodule. This ensures that your tests are runnable by anyone who clones your repository, without requiring a system-wide installation.

```bash
# Add bats-core and helper libraries as submodules
git submodule add https://github.com/bats-core/bats-core.git test/bats
git submodule add https://github.com/bats-core/bats-support.git test/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git test/test_helper/bats-assert
```

This creates a `test` directory with `bats` and its helper libraries.

## Writing Tests

### Basic Test Structure

A Bats test file is a Bash script with special syntax for defining test cases. Each test case is a function with a `@test` annotation.

```bash
#!/usr/bin/env bats

@test "A simple test case" {
  # Your test code here
  [ 1 -eq 1 ]
}
```

### Executing Commands with `run`

The `run` command is a powerful helper for executing commands and inspecting their output and exit status.

```bash
@test "invoking a command" {
  run my_command "some argument"

  # $status contains the exit status of the command
  [ "$status" -eq 0 ]

  # $output contains the combined stdout and stderr
  [ "$output" = "expected output" ]

  # ${lines[@]} is an array of output lines
  [ "${lines[0]}" = "first line of output" ]
}
```

`run` can also perform implicit checks on the exit status:
- `run -N command`: Expects exit status `N`.
- `run ! command`: Expects a non-zero exit status.

### Sharing Code with `load`

The `load` command allows you to source shared Bash code from other files, relative to the current test file. This is useful for helper functions and test setup.

```bash
# In test/my_test.bats
load 'test_helper/common.bash'

@test "a test using a helper" {
  my_helper_function
}
```

### Setup and Teardown

Bats provides several hooks for setting up and tearing down the test environment:

- **`setup()` and `teardown()`:** Run before and after each individual test case in a file.
- **`setup_file()` and `teardown_file()`:** Run once per file, before the first test and after the last test.
- **`setup_suite()` and `teardown_suite()`:** Run once for the entire test suite, defined in a separate `setup_suite.bash` file.

```bash
setup_file() {
  # Runs once before all tests in this file
}

setup() {
  # Runs before each test
}

teardown() {
  # Runs after each test
}

teardown_file() {
  # Runs once after all tests in this file
}
```

### Skipping Tests

You can skip tests using the `skip` command.

```bash
@test "a skipped test" {
  skip "This test is not ready yet"
  # This code will not be executed
}

@test "a conditionally skipped test" {
  if [ -z "$SOME_ENV_VAR" ]; then
    skip "SOME_ENV_VAR is not set"
  fi
}
```

### Tagging Tests

You can tag tests to categorize and filter them.

```bash
# bats test_tags=slow,network

@test "a slow test that requires network" {
  # ...
}
```

## Running Tests

To run your tests, invoke the `bats` executable with the path to your test files or directories.

```bash
# Run a single file
./test/bats/bin/bats test/my_test.bats

# Run all .bats files in a directory
./test/bats/bin/bats test/

# Run recursively
./test/bats/bin/bats -r test/
```

### Command-Line Options

- `--help`, `-h`: Show help.
- `--formatter <formatter>`: Specify the output formatter (`tap`, `junit`, or a custom one).
- `--report-formatter <formatter>`: Generate a report file.
- `--output <dir>`: Directory to store report files.
- `--jobs <N>`: Run tests in parallel using `N` jobs (requires GNU `parallel`).
- `--filter <regex>`: Run only tests whose names match the regex.
- `--filter-tags <tags>`: Run only tests with matching tags.

## Gotchas and FAQ

- **`run` and Pipes:** `run my_command | grep foo` will not work as expected because the pipe has higher precedence. Use a helper function or `run bash -c 'my_command | grep foo'`.
- **`run` and Subshells:** `run` executes commands in a subshell, so variable changes won't persist.
- **`load` and `.sh` files:** `load` automatically appends `.bash`. To load a `.sh` file, use `source my_file.sh`.
- **Debugging:** Use `assert_*` functions from `bats-assert` for better failure output. To see the output of a command under `run`, you must print the `$output` variable.
- **File Descriptor 3:** If Bats hangs, it might be due to a background process holding open file descriptor 3. Close it explicitly: `my_command 3>&- &`.

## Helper Libraries

This section will be expanded to cover the following helper libraries:

### bats-assert

`bats-assert` is a helper library providing common assertions for Bats. It depends on `bats-support`.

**Key Assertions:**

- **`assert` / `refute`**: Assert that a given expression evaluates to true or false.
- **`assert_equal` / `assert_not_equal`**: Assert that two parameters are equal or not equal.
- **`assert_success` / `assert_failure`**: Assert that the exit status of the last `run` command was 0 or non-zero.
- **`assert_output` / `refute_output`**: Assert that the output of the last `run` command does or does not contain the given content. Supports literal, partial, and regex matching.
- **`assert_line` / `refute_line`**: Assert that a specific line of the output does or does not contain the given content.
- **`assert_regex` / `refute_regex`**: Assert that a parameter does or does not match a given regex.
- **`assert_stderr` / `refute_stderr`**: Assert that the stderr of the last `run` command (with `--separate-stderr`) does or does not contain the given content.

**Example:**

```bash
@test "assert_output example" {
  run echo "hello world"
  assert_output "hello world"
  assert_output --partial "hello"
}
```

### bats-file

`bats-file` provides common filesystem-related assertions and helpers. It depends on `bats-support`.

**Key Functions:**

- **`assert_exists` / `assert_not_exists`**: Assert that a file or directory exists or does not exist.
- **`assert_file_exists` / `assert_dir_exists`**: More specific existence assertions.
- **`assert_file_executable`**: Assert that a file is executable.
- **`assert_file_contains` / `assert_file_not_contains`**: Assert that a file contains or does not contain a regex match.
- **`assert_files_equal`**: Assert that two files have the same content.
- **`temp_make`**: Creates a temporary directory for a test.
- **`temp_del`**: Deletes a temporary directory.

**Example:**

```bash
@test "bats-file example" {
  local temp_dir
  temp_dir="$(temp_make)"
  touch "$temp_dir/my_file"
  assert_exists "$temp_dir/my_file"
  temp_del "$temp_dir"
}
```

### bats-mock

`bats-mock` is a library for mocking and stubbing commands.

**Key Functions:**

- **`stub <command> [plan]`**: Creates a stub for a command with a plan for expected arguments and return values.
- **`unstub <command>`**: Removes the stub and verifies that the plan was fulfilled.

**Example:**

```bash
@test "bats-mock example" {
  # Stub the 'date' command
  stub date "-r 222 : echo 'I am stubbed!'"

  # The function under test calls 'date -r 222'
  result="$(format_date)"

  [ "$result" == 'I am stubbed!' ]

  # Clean up the stub
  unstub date
}
```

### bats-support

`bats-support` is a supporting library that provides common functions for other Bats helper libraries. It is a dependency for `bats-assert` and `bats-file`.

**Key Features:**

- **`fail <message>`**: Displays an error message and fails the test.
- **Output Formatting**: Provides functions for creating formatted, human-readable output for assertions, including two-column and multi-line formats.
- **`batslib_is_caller`**: Allows restricting a helper function to be called only from specific locations (e.g., only from `teardown`).
