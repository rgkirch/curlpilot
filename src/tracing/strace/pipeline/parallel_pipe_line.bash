# Define your log files
LOG_FILES="/tmp/tmp.ULE8Mo2737/strace-logs/trace.*"

# Cat the logs and pipe them to parallel
cat $LOG_FILES | parallel --keep-order --line-buffer '2>&1 ./pipe_line.bash'

# `cat $LOG_FILES`: Streams all your log lines.
# `| parallel`: Feeds one line at a time to a new process.
# `--keep-order`: Buffers the output and prints it in the original line order (this is your key insight).
# `--line-buffer`: Flushes output on every line, so you see results progressively.
# `'2>&1 ./run_pipeline_linewise.bash'`: This is the "black box." It runs your script and redirects its `stderr` (your debug prints) to its `stdout`, so `--keep-order` can capture and buffer *everything* correctly.
