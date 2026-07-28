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

    function lock(): string {
        if (!lockScreen)
            return "error: lock not ready";
        lockScreen.lock();
        return "ok";
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
            authError: lockScreen.authError
        });
    }
}
