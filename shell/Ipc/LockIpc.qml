import Quickshell.Io
import qs.Services

// `qs ipc call lock lock|isLocked|status` (spec's IPC list, §8). Every verb
// goes through LockService, which decides between the built-in surface and
// the external locker `lock.command` names; nothing here knows which of the
// two ran.
//
// No unlock() verb on purpose: Lock.qml's own submitPassword()/PamContext
// flow is the only unlock path, and a headless "type this password" hook
// would bypass the exact input and PAM wiring a real unlock exercises, so
// dev/smoke.sh --lock authenticates with real synthetic keystrokes (wtype)
// instead.
IpcHandler {
    target: "lock"

    // The command a `lock-before-sleep` systemd unit calls before suspend
    // (spec §8) must keep an exit-0-always contract so a lock failure can
    // never block suspend. `qs ipc call` itself only exits nonzero when the
    // target/function lookup fails or the call never completes at the wire
    // level (never on the QML function's own return value), and LockService
    // catches anything the surface throws rather than letting it surface as
    // an uncaught error.
    function lock(): string {
        return LockService.lock();
    }

    // "unknown", not "false", while an external locker owns the session: it
    // never reports back, and false would be a claim this shell cannot make.
    function isLocked(): string {
        if (LockService.external)
            return "unknown";
        if (!LockService.lockScreen)
            return "error: lock not ready";
        return LockService.isLocked() ? "true" : "false";
    }

    function status(): string {
        const state = LockService.status();
        if (state === null)
            return "error: lock not ready";
        return JSON.stringify(state);
    }
}
