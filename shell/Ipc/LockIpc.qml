import Quickshell.Io

// `qs ipc call lock lock|isLocked|status` — spec's IPC list (§8). No
// unlock() verb here on purpose: Lock.qml's own submitPassword()/PamContext
// flow is the only unlock path, and a headless "type this password" hook
// would bypass the exact TextInput/PAM wiring a real unlock exercises —
// dev/smoke-niri.sh --lock authenticates with real synthetic keystrokes
// (wtype) instead.
IpcHandler {
    target: "lock"

    // Set from shell.qml — the single Lock instance (same reasoning as
    // MenuIpc's `menu` property: one instance, no singleton of its own).
    // Named lockScreen rather than `lock` because the verb below is named
    // `lock` too — QML can't have a property and a method share one name.
    property var lockScreen: null

    // The command a `lock-before-sleep` systemd unit calls before suspend
    // (spec §8) must keep an exit-0-always contract so a lock failure can
    // never block suspend — `qs ipc call` itself already only exits nonzero
    // when the target/function lookup fails or the call never completes at
    // the wire level (never on the QML function's own return value), but
    // the try/catch is defense in depth: WlSessionLock's own docs warn a
    // dying lock still leaves the screen forcibly locked, so this must
    // never let an unexpected exception surface as an uncaught error
    // instead of the ordinary "error: ..." string every other IPC failure
    // path here already returns.
    function lock(): string {
        if (!lockScreen)
            return "error: lock not ready";
        try {
            lockScreen.lock();
            // WlSessionLock::realizeLockTarget() can silently give up and
            // unlock again (no compositor ext-session-lock-v1 support, no
            // surface component, or the surface never producing a
            // WlSessionLockSurface) without throwing — reading `locked`
            // straight back catches all three fail-open paths instead of
            // reporting "ok" while the session stays unlocked. Safe despite
            // WlSessionLock's own lockStateChanged() not firing on the lock
            // path (see Lock.qml's lock() comment): this is a fresh
            // imperative read, not a stale binding.
            if (!lockScreen.locked)
                return "error: lock failed to acquire session lock";
            return "ok";
        } catch (e) {
            console.warn("LockIpc: lock() failed:", e.message);
            return "error: " + e.message;
        }
    }

    function isLocked(): string {
        if (!lockScreen)
            return "error: lock not ready";
        return lockScreen.locked ? "true" : "false";
    }

    function status(): string {
        if (!lockScreen)
            return "error: lock not ready";
        return JSON.stringify({
            locked: lockScreen.locked,
            secure: lockScreen.secure,
            authError: lockScreen.authError,
            blanked: lockScreen.blanked
        });
    }
}
