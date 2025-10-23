set -euo pipefail
#set -x

LOG_FILES="/tmp/tmp.FnmDVBsD4z/strace-logs/trace.*"

cat $LOG_FILES | parallel --keep-order --line-buffer 'printf "%s\n" {} | ./pipe_line.bash 2>&1'
