# A Guide to SSA-Style (Immutable) Bash Scripting

This guide outlines a style of Bash scripting that favors principles from Single Static Assignment (SSA) and functional programming. The core idea is to **minimize mutable state**. Instead of creating variables and changing them over and over, you create new variables by transforming old ones.

This discipline dramatically reduces a class of common and subtle bugs, such as the order-of-operations and race-condition bugs we discovered, making scripts safer, more predictable, and easier to reason about.

---

## 1. The Core Principles

### a. Immutability by Convention: Use `readonly`

The `readonly` (or `declare -r`) keyword is your most important tool. It's a contract that says, "This variable's value is set once and will not change."

-   **Use it for:** Configuration values, script arguments, file paths, and any variable that represents a completed transformation.
-   **Don't use it for:** Variables that *must* change, such as counters in a `while` loop or the iterative variables within a loop's body.

**Bad (Mutable):**
``` bash
# The `api_endpoint` variable can be accidentally changed later in the script.
api_endpoint="https://api.example.com/v1"
# ... 50 lines of code ...
api_endpoint="http://test-server/v1" # Accidental reassignment
```

**Good (Immutable):**
``` bash
# This variable is now protected from accidental modification.
readonly api_endpoint="https://api.example.com/v1"

# This would cause the script to fail immediately, revealing the bug.
# api_endpoint="http://test-server/v1"  # Error: readonly variable
```

### b. Transformation via Pipelines and Command Substitution

This is the heart of functional shell scripting. A pipeline (`|`) is a pure transformation. Each step takes input and produces output without side effects. Command substitution (`$()`) captures the final result into a *new* immutable variable.

This approach is almost always superior to building up a value in a loop.

**Bad (Mutable Loop):**
``` bash
# State is built up incrementally, making the loop's final result
# dependent on every single step.
keys=""
for k in $(jq -r 'keys[]' spec.json); do
  keys+="${k}," # Mutating 'keys' in a loop
done
```

**Good (Pipeline Transformation):**
``` bash
# The data flows through a series of transformations, and the final
# result is captured in a single, clean assignment.
readonly keys=$(jq -r 'keys[]' spec.json | paste -sd ",")
```

### c. Isolate State with Functions

Functions should be treated as pure transformations whenever possible. A function should take arguments as input, operate on them using `local` variables, and `echo` its final result to standard output. It should not modify global state.

This makes functions predictable and easily testable units of logic.

**Bad (Function with Side Effects):**
``` bash
# This function modifies a global variable, which is an invisible side effect.
# It's hard to know what this function does without reading its source code.
raw_json="{}"
add_key_value() {
  key="$1"
  val="$2"
  raw_json=$(echo "$raw_json" | jq --arg k "$key" --arg v "$val" '.[$k] = $v')
}

add_key_value "user" "admin"
```

**Good (Pure Function):**
``` bash
# This function is a pure transformation. It takes JSON as input and
# returns a new JSON string as output, with no side effects.
add_key_value() {
  local json_in="$1"
  local key="$2"
  local val="$3"
  echo "$json_in" | jq --arg k "$key" --arg v "$val" '.[$k] = $v'
}

readonly initial_json="{}"
readonly final_json=$(add_key_value "$initial_json" "user" "admin")
```

---

## 2. Practical Application: The Bug We Fixed

Our argument parser provides the perfect real-world example.

**The Buggy, Mutable Version:**
``` bash
# Fails if ARG_NAME_KEBAB is `api-key=SECRET`
# First line mutates ARG_NAME_KEBAB to `api-key`.
ARG_NAME_KEBAB="${ARG_NAME_KEBAB%%=*}"
# Second line now operates on the mutated data, failing to find the value.
VALUE="${ARG_NAME_KEBAB#*=}" # Incorrectly becomes "api-key"
```

**The Safe, SSA-Style Version:**
``` bash
# By using the original, pristine `ARG` variable as the source for the value,
# we create two independent transformations, preventing the bug.
readonly final_value="${ARG#*=}"
readonly final_key_kebab="${arg_name_kebab%%=*}"

# Now, update the loop's mutable state from our new, correct variables.
value="$final_value"
arg_name_kebab="$final_key_kebab"
```

---

## 3. Finding the Idiomatic Balance

The goal is not to be dogmatic, but to be safe. You cannot make every variable `readonly`.

-   **DO** use `readonly` for major data structures that represent the state of the script between transformations (e.g., `USER_SPEC_JSON`, `ARG_SPEC_JSON`, `FINAL_JSON`).
-   **DO NOT** use `readonly` for transient variables inside loops that *must* be reassigned on each iteration (e.g., `ARG` in our `while` loop, or `key` in our `for` loop).

By favoring this style, you make your scripts more robust and easier to debug, as the flow of data is explicit and the possibility of accidental state modification is greatly reduced.
