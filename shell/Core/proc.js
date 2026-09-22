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
// KillMode=process deliberately: outside a uwsm session, apps launched from
// the launcher share the shell's cgroup and have to survive a restart.
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

// argv that launches a desktop entry, or one of its actions, as its own scope
// in app-graphical.slice rather than as a child in formalshell.service's
// cgroup. systemd-oomd can then kill that one app instead of the shell and
// everything it launched, and a shell restart never reaches it. uwsm parses
// the entry itself, so Exec field codes and Terminal=true behave as in any
// launcher (DesktopEntry.execute() ignores both). An action goes by its
// parsed command: uwsm only resolves actions by id, which DesktopAction does
// not document. Returns null outside a uwsm session (the nested smoke rig
// has no app slice to land in); the caller keeps execute() then.
function appLaunch(uwsmSession, entry, action) {
    if (!uwsmSession || !entry)
        return null;
    var target = action ? (action.command || []) : [entry.id + ".desktop"];
    if (target.length === 0)
        return null;
    return ["uwsm", "app", "--"].concat(target);
}
