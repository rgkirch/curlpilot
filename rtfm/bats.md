
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

Bats provides hooks for setting up and tearing down test environments at different scopes. Understanding their execution context is critical for using them correctly.

- **`setup()` and `teardown()`:** Run before and after each individual test case in a file.
- **`setup_file()` and `teardown_file()`:** Run once per file, before the first test and after the last test.

#### `setup()` vs. `setup_file()` Execution Context

A crucial difference exists between the file-level and test-level hooks, confirmed by analysis of the Bats source code:

-   **`setup_file()` and `teardown_file()`** run in a **parent process** (`bats-exec-file`) for the entire test file. 
    -   This parent process **does not** have the Bats helper functions (like `load` and `run`) loaded.
    -   **Use Case:** Ideal for expensive, file-level setup that does not require Bats-specific helpers. For example, creating a temporary directory, starting a background service, or compiling an artifact that all tests in the file will use.
    -   **Limitation:** Because they run in this different context, they **do not have access to Bats helper functions like `load`** or special variables like `$BATS_TEST_NAME`.

-   **`setup()` and `teardown()`** run in a **separate child process** (`bats-exec-test`) for each individual test case.
    -   This child process **does** load the Bats helper library (`test_functions.bash`), making functions like `load` and `run` available.
    -   **Use Case:** Perfect for preparing the environment for each individual test. This is where you should use `load` to source helper scripts.
    -   **Advantage:** They have full access to the Bats runtime environment, including all helper functions and special variables.

```bash
# good_practices.bats

setup_file() {
  # Runs once before all tests in this file.
  # OK: Create a directory that all tests can use.
  mkdir -p /tmp/my_test_dir
}

setup() {
  # Runs before each test in a separate process where helpers are available.
  # OK: Load helpers. This works because `setup` has access to the Bats runtime.
  load 'test_helper/common.bash'
}

teardown() {
  # Runs after each test.
  # Clean up resources created in setup().
}

teardown_file() {
  # Runs once after all tests in this file.
  # OK: Clean up the directory created in setup_file().
  rm -rf /tmp/my_test_dir
}

@test "a test using a loaded helper" {
  # my_helper_function is available here because it was loaded in setup()
  my_helper_function
}
```

#### Suite-Level Setup

- **`setup_suite()` and `teardown_suite()`:** Run once for the entire test suite, defined in a separate `setup_suite.bash` file. These are for global setup and teardown actions across all test files.

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

#### Focusing on a Single Test

To focus on a single test or a small group of tests, you can use the special `bats:focus` tag. When Bats encounters a test with this tag, it will only run the tests that are marked with `bats:focus` and will ignore all other tests.

This is useful during development when you want to repeatedly run a specific test without running the entire test suite.

```bash
# bats test_tags=bats:focus
@test "a focused test" {
  # This test will run
}

@test "another test" {
  # This test will be skipped
}
```

**Important:** When tests are run in focus mode, the exit code of a successful run is forced to `1`. This is a safety measure to prevent you from accidentally committing focused tests and having your CI build pass on a subset of your tests.

If you need the true exit code (e.g., for a `git bisect` operation), you can set the `BATS_NO_FAIL_FOCUS_RUN=1` environment variable.


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
