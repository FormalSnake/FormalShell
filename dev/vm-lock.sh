#!/usr/bin/env bash
# Hands out one of two test VM slots to parallel worktrees. `dev/vm.sh sync`
# rsyncs the caller's working tree over a VM's single checkout with --delete,
# so two runs in one VM would replace each other's files mid-run; each slot is
# its own VM behind its own lock. Slot 0 keeps /tmp/formalshell-vm.lock. When
# every slot is busy this polls until one frees. The command runs with
# FS_VM_SLOT exported, which dev/vm.sh and the justfile recipes read, and the
# slot's VM is started first if it is not up. macOS ships no flock(1), hence
# python.
#
#   dev/vm-lock.sh just vm-smoke --panel audio
set -euo pipefail
vm_sh="$(cd "$(dirname "$0")" && pwd)/vm.sh"
slots="${FS_VM_SLOTS:-2}"
# -c, not a heredoc: the command inherits stdin, and dev/native-check.sh
# pipes its packages through it.
exec python3 -c '
import fcntl, os, subprocess, sys, time
vm_sh, slots = sys.argv[1], int(sys.argv[2])
cmd = sys.argv[3:]
def path(n):
    return "/tmp/formalshell-vm.lock" if n == 0 else "/tmp/formalshell-vm-%d.lock" % n
while True:
    for n in range(slots):
        lock = open(path(n), "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            lock.close()
            continue
        os.environ["FS_VM_SLOT"] = str(n)
        print("vm-lock: slot %d" % n, file=sys.stderr)
        up = subprocess.run([vm_sh, "status"], stdout=subprocess.PIPE, text=True)
        if "ssh reachable" not in up.stdout:
            subprocess.run([vm_sh, "start"], stdout=sys.stderr, check=True)
        sys.exit(subprocess.call(cmd))
    time.sleep(3)
' "$vm_sh" "$slots" "$@"
