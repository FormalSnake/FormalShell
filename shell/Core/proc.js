.pragma library

// Long-lived children of the shell, wrapped so the kernel kills them when
// the shell dies.
//
// Quickshell kills a managed child from `Process`'s destructor (pinned
// 43d4fa9, src/io/process.cpp:31), which only runs on a clean QML teardown,
// and it installs no SIGTERM handler at all. `systemctl --user restart
// formalshell` therefore kills the shell outright, and every child it owned
// is reparented to systemd and left running: g815 was carrying seven
// orphaned `wl-paste --watch` pairs, one per restart that day (2026-08-26).
// systemd does not clean them up either, because the unit sets
// KillMode=process deliberately, apps launched from the launcher share the
// shell's cgroup and have to survive a restart.
//
// PR_SET_PDEATHSIG closes every exit path the destructor misses, SIGKILL
// included. setpriv sets it and execs in place, so the wrapped command is
// still the shell's own direct child and `Process.processId` still reports
// the pid a signal has to reach, which NightLightService's SIGUSR1
// handshake depends on. util-linux is on the wrapper's PATH
// (nix/package.nix), so there is nothing here to fall back to.
//
// Only for a child that outlives its own call. A one-shot exits long before
// a restart can orphan it, and wrapping it would buy an extra exec for
// nothing.
function dieWithParent(argv) {
    return ["setpriv", "--pdeathsig", "TERM", "--"].concat(argv || []);
}
