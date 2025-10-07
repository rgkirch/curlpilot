## 4.3.1 The `set` Builtin

The `set` builtin is complex and deserves its own section. It allows you to change shell options, set positional parameters, or display the names and values of shell variables.

### Synopsis

```shell
set [-abefhkmnptuvxBCEHPT] [-o option-name] [--] [-] [argument ...]
set [+abefhkmnptuvxBCEHPT] [+o option-name] [--] [-] [argument ...]
set -o
set +o
```

- If no options or arguments are supplied, `set` displays the names and values of all shell variables and functions, sorted according to the current locale. The output format may be reused as input for setting or resetting the currently-set variables. Read-only variables cannot be reset. In POSIX mode, only shell variables are listed.
- When options are supplied, they set or unset shell attributes. Any arguments remaining after option processing replace the positional parameters.

---

### Options

#### Basic Options

- **`-a`**  
  Each variable or function created or modified is marked for export to the environment of subsequent commands.

- **`-b`**  
  Reports status of terminated background jobs immediately, rather than before printing the next primary prompt or after a foreground command exits. Effective only with job control enabled.

- **`-e`**  
  Exit immediately if a pipeline or command returns a non-zero status. Exceptions apply for commands following `while`, `until` or in an `if` statement, among others. An ERR trap (if set) executes before exit. This option applies separately to the shell and each subshell environment.

- **`-f`**  
  Disables filename expansion (globbing).

- **`-h`**  
  Locate and remember (hash) commands as they are looked up for execution. Enabled by default.

- **`-k`**  
  All assignment statements are placed in the environment for a command, not just those that precede the command name.

- **`-m`**  
  Enables job control; all processes run in separate process groups. Prints background job exit status when completed.

- **`-n`**  
  Read commands without executing them. Useful for syntax checking scripts. Ignored by interactive shells.

- **`-o option-name`**  
  Set the option corresponding to `option-name`.  
  - If `-o` is supplied without an option name, prints current shell options.  
  - If `+o` is supplied without an option name, prints set commands to recreate current options.

#### `-o option-name` Valid Names

- **`allexport`** — Same as `-a`
- **`braceexpand`** — Same as `-B`
- **`emacs`** — Use Emacs-style line editing (affects `read -e`)
- **`errexit`** — Same as `-e`
- **`errtrace`** — Same as `-E`
- **`functrace`** — Same as `-T`
- **`hashall`** — Same as `-h`
- **`histexpand`** — Same as `-H`
- **`history`** — Enable command history (default in interactive shells)
- **`ignoreeof`** — Prevent interactive shell from exiting on EOF
- **`keyword`** — Same as `-k`
- **`monitor`** — Same as `-m`
- **`noclobber`** — Same as `-C`
- **`noexec`** — Same as `-n`
- **`noglob`** — Same as `-f`
- **`nolog`** — Currently ignored
- **`notify`** — Same as `-b`
- **`nounset`** — Same as `-u`
- **`onecmd`** — Same as `-t`
- **`physical`** — Same as `-P`
- **`pipefail`** — Pipeline’s return value is that of the last command with non-zero status, or zero if all succeed. Disabled by default.
- **`posix`** — Enable POSIX mode; Bash operates as a strict superset of the POSIX standard.
- **`privileged`** — Same as `-p`
- **`verbose`** — Same as `-v`
- **`vi`** — Use Vi-style line editing (affects `read -e`)
- **`xtrace`** — Same as `-x`

#### Additional Options

- **`-p`**  
  Turn on privileged mode. Certain environment files and variables are not processed or inherited. Effective user/group ID handling depends on this flag.

- **`-r`**  
  Enable restricted shell mode. Cannot be unset once set.

- **`-t`**  
  Exit after reading and executing one command.

- **`-u`**  
  Treat unset variables or parameters (other than ‘@’ or ‘*’) as errors during parameter expansion. Writes an error to stderr and non-interactive shells exit.

- **`-v`**  
  Print shell input lines to stderr as they are read.

- **`-x`**  
  Print a trace of simple commands and their arguments or word lists to stderr after expansion and before execution.

- **`-B`**  
  Enable brace expansion (default on).

- **`-C`**  
  Prevent output redirection from overwriting existing files. `>|` overrides this and forces creation.

- **`-E`**  
  ERR trap inheritance for functions, command substitutions, and subshells.

- **`-H`**  
  Enable ‘!’ style history substitution (default for interactive shells).

- **`-P`**  
  Use the physical directory structure rather than resolving symbolic links (`cd`).  
  **Example:**
  ```
  $ cd /usr/sys; echo $PWD
  /usr/sys
  $ cd ..; pwd
  /usr

  # With set -P:
  $ cd /usr/sys; echo $PWD
  /usr/local/sys
  $ cd ..; pwd
  /usr/local
  ```

- **`-T`**  
  DEBUG and RETURN trap inheritance for functions, command substitutions, and subshells.

- **`--`**  
  If no arguments follow, unset positional parameters. Otherwise, positional parameters are set to the arguments, even if they begin with a ‘-’.

- **`-`**  
  Signals the end of options; assigns all remaining arguments to positional parameters. Turns off `-x` and `-v`. If no arguments remain, positional parameters are unchanged.

---

#### Turning Options Off

Using ‘+’ instead of ‘-’ turns the given options off. They can also be set when invoking the shell. The current options are stored in `$-`.

---

### Positional Parameters

Any remaining N arguments are assigned to `$1`, `$2`, ..., `$N`. The special parameter `#` is set to `N`.

---

### Return Status

The return status is always zero unless an invalid option is supplied.
