#!/usr/bin/env bash
# Serialises VM access from parallel worktrees. `dev/vm.sh sync` rsyncs the
# caller's working tree over the VM's single checkout with --delete, so two
# runs in flight would replace each other's files mid-run. macOS ships no
# flock(1), hence python.
#
#   dev/vm-lock.sh just vm-smoke --panel audio
set -euo pipefail
# -c, not a heredoc: the command inherits stdin, and dev/native-check.sh
# pipes its packages through it.
exec python3 -c '
import fcntl, subprocess, sys
with open("/tmp/formalshell-vm.lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    sys.exit(subprocess.call(sys.argv[1:]))
' "$@"
