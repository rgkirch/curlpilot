set -euo pipefail
#set -x

source ./log_dir.bash

cat $LOG_FILES_PATTERN | parallel --keep-order --line-buffer 'printf "%s\n" {} | ./pipe_line.bash 2>&1'
