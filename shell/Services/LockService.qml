pragma Singleton
import Quickshell
import QtQuick
import qs.Core
import qs.Compositor
import "lock.js" as Lock

// The one lock trigger (M45 D2). `lock lock` over IPC (and with it
// formalshell-lock-before-sleep, which calls that route), the `lock` hot
// corner, `screensaver.lockAfterSeconds`' chain and the launcher's Lock row
// all come through here, so the choice between the built-in surface and an
// external locker is made in one place rather than five.
//
// `lock.command` (argv list, default empty) names that external locker:
// hyprlock, swaylock, `loginctl lock-session`. It owns the session on its
// own terms and never reports back, which is why `isLocked` is null while
// one is configured. False would be a claim this shell cannot make.
Singleton {
    id: root

    // The built-in WlSessionLock surface (Surfaces/Lock/Lock.qml), wired
    // from shell.qml, which is the only file that can hold it.
    property var lockScreen: null

    readonly property var command: Lock.argv(Config.get("lock.command", []))
    readonly property bool external: root.command.length > 0

    // A function, not a property: WlSessionLock::setLocked() only emits
    // lockStateChanged() on its unlock path (verified against
    // session_lock.cpp, see Lock.qml's own lock() comment), so a binding on
    // `lockScreen.locked` would cache false at construction and never
    // re-evaluate. Every caller here needs a fresh read.
    //
    // null means "not this shell's to say": an external locker owns the
    // session, or the surface is not wired yet.
    function isLocked() {
        if (root.external)
            return null;
        return root.lockScreen ? root.lockScreen.locked : null;
    }

    function lock() {
        return Lock.lock(root.command,
            function (argv) { CompositorService.spawn(argv); },
            function () { return root._raise(); });
    }

    function _raise() {
        if (!root.lockScreen)
            return "error: lock not ready";
        try {
            root.lockScreen.lock();
            // WlSessionLock::realizeLockTarget() can give up and unlock
            // again without throwing (no compositor ext-session-lock-v1, no
            // surface component, or the surface never producing a
            // WlSessionLockSurface), so the state is read straight back
            // rather than inferred from the call returning.
            if (!root.lockScreen.locked)
                return "error: lock failed to acquire session lock";
            return "ok";
        } catch (e) {
            console.warn("LockService: lock() failed:", e.message);
            return "error: " + e.message;
        }
    }

    function status() {
        if (!root.external && !root.lockScreen)
            return null;
        return Lock.status(root.command, root.lockScreen);
    }
}
