### \#\# The Definitive Guide: Why the Simple `wait` is Correct

The simple method of redirecting a command's output to background `tee` processes and using a generic `wait` is fundamentally robust, correct, and sufficient. More complex solutions involving explicit file descriptor management (`exec {fd}>&-`) are unnecessary and based on a misunderstanding of how shells and operating systems fundamentally work.

Here is the correct and robust pattern:

```bash
# Create pipes and set up automatic cleanup on script exit
mkfifo "$stdout_pipe" "$stderr_pipe"
trap 'rm -f "$stdout_pipe" "$stderr_pipe"' EXIT

# Start background readers FIRST. They will wait for data.
tee -a "$stdout_file" < "$stdout_pipe" &
local tee_stdout_pid=$!
tee -a "$stderr_file" < "$stderr_pipe" >&2 &
local tee_stderr_pid=$!

# Run the command and redirect its output
"${exec_cmd[@]}" >"$stdout_pipe" 2>"$stderr_pipe"

# Wait for all background jobs (the tees) to finish
wait "$tee_stdout_pid" "$tee_stderr_pid"
```

-----

### \#\# The Core Principle: The OS Cleans Up After Its Children

This pattern works because of a non-negotiable rule enforced by the operating system: **When a process terminates, the OS automatically closes all of its open file descriptors.**

Any objection to the simple code stems from a fear of a "deadlock," where the `tee` processes never exit because the pipe is held open. This fear is unfounded. Here is the exact sequence of events:

1.  **Fork:** The shell needs to run your command (`"${exec_cmd[@]}"`). To do this, it first creates a **child process**—a temporary, isolated clone of itself.
2.  **Redirect (in the Child):** *Inside this new child process*, the shell sets up the redirection. It connects the child's standard output to the write-end of `$stdout_pipe`. The parent shell's file descriptors are **not involved**.
3.  **Exec:** The child process then transforms into your command (`exec_cmd`), inheriting the redirected file descriptors.
4.  **Exit & Automatic Cleanup:** The command finishes and the child process exits. The moment it exits, the operating system **forcibly closes all file descriptors that belonged to that child**.
5.  **EOF Signal:** The OS's closure of the write-end of the pipe sends the universal "End-of-File" (EOF) signal to the readers.
6.  **`tee` Finishes:** The `tee` processes, which were waiting for data, receive the EOF. They know for certain no more data is coming, so they flush their buffers and exit cleanly.
7.  **`wait` Succeeds:** The parent script's `wait` command, which was paused, sees that the background `tee` jobs have finished and proceeds.

There is no possibility of a deadlock. The entire lifecycle of the file handle that writes to the pipe is contained within the temporary child process. Its cleanup is guaranteed by the OS.

-----

### \#\# Debunking Common Objections

  * **Objection:** "But what about group commands like `{...}`? The parent shell runs those, so it must hold the pipe open\!"

      * **Reality:** This is false. While a group command runs in the parent's context, the redirection (`>`) applied to it is **scoped only to that block**. When the block finishes, the shell automatically closes the file descriptor. No deadlock occurs.

  * **Objection:** "What if the child process is buggy and opens other file descriptors? Isn't the complex cleanup safer?"

      * **Reality:** No. This demonstrates a misunderstanding of the **process boundary**. A child process cannot create a file descriptor that the parent needs to clean up. When the misbehaving child exits, the OS cleans up *all* of its file descriptors, regardless. The parent's cleanup ritual is a pointless action on a problem that the OS has already solved.

-----

### \#\# The "Temporary Workshop" Analogy  analogy

Think of your main script as a **Foreman**.

1.  To get a job done (`exec_cmd`), the Foreman hires a **Temp Worker** and puts them in a **temporary, sealed workshop** (the child process).
2.  The Worker connects their hoses (`stdout`) to the pipes you laid out. These are the Worker's connections, not the Foreman's.
3.  When the Worker finishes, they leave. The moment they do, the **entire workshop and everything in it instantly vanishes**, and the hoses are automatically disconnected (OS cleanup).
4.  The complex `exec {fd}>&-` code is the equivalent of the Foreman walking over to the empty lot where the workshop *used* to be and performing a ritual to lock a door that no longer exists. It's a useless action that accomplishes nothing.

In short, trust the operating system. It is designed to handle this perfectly. The simple code is not just "good enough"—it is the most correct, robust, and idiomatic way to perform this task.
