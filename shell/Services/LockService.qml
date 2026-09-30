pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Core
import qs.Compositor
import "lock.js" as Lock
import "../Core/proc.js" as Proc

// The one lock trigger (M45 D2). `lock lock` over IPC, logind's
// PrepareForSleep, the `lock` hot corner, `screensaver.lockAfterSeconds`'
// chain and the launcher's Lock row all come through here, so the choice between the built-in surface and an
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

    // null until the lookup below answers, so a lock fired in the first
    // moments after start still takes the configured locker.
    property var _missing: null

    onCommandChanged: root._lookUp()
    Component.onCompleted: root._lookUp()

    function _lookUp() {
        root._missing = null;
        if (!root.external)
            return;
        lookup.running = false;
        lookup.command = ["sh", "-c", 'command -v "$1" >/dev/null 2>&1', "sh", root.command[0]];
        lookup.running = true;
    }

    Process {
        id: lookup
        onExited: exitCode => {
            root._missing = exitCode !== 0;
            if (root._missing)
                console.warn("LockService: lock.command", root.command[0], "is not on PATH, the built-in lock is used instead");
        }
    }

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
            function () { return root._raise(); },
            root._missing);
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
        const state = Lock.status(root.command, root.lockScreen);
        state.beforeSleep = {
            enabled: root.beforeSleep,
            monitoring: sleepMonitor.running,
            inhibiting: sleepInhibitor.running,
            last: root._lastSleep
        };
        return state;
    }

    // Spec §8: lock before suspend, and never block it. logind signals
    // PrepareForSleep(true), then waits for every delay inhibitor to be
    // released (or InhibitDelayMaxSec to run out) before it suspends, so
    // the lock lands before the machine sleeps only while one is held. A
    // lock that fails or never lands just lets go early; logind's own
    // timeout covers a shell too stuck to let go at all.
    readonly property bool beforeSleep: Config.get("lock.beforeSleep", true) !== false

    property bool _preparing: false
    property var _sleepResult: null
    property real _sleepStartMs: 0
    // What the last PrepareForSleep(true) did: lock()'s reply, why the
    // inhibitor was let go, and the wall clock of each step.
    property var _lastSleep: null

    function _onPrepareForSleep(sleeping) {
        if (!sleeping) {
            root._preparing = false;
            sleepReleaseTimer.stop();
            return;
        }
        if (root._preparing)
            return;
        root._preparing = true;
        root._sleepStartMs = Date.now();
        root._sleepResult = root.isLocked() === true ? "already" : root.lock();
        root._lastSleep = { result: root._sleepResult, release: null, preparedAt: root._sleepStartMs, releasedAt: null };
        sleepReleaseTimer.start();
        root._checkSleepRelease();
    }

    function _checkSleepRelease() {
        const why = Lock.sleepRelease(root.external && root._missing !== true, root._sleepResult,
            root.lockScreen ? root.lockScreen.secure : null, Date.now() - root._sleepStartMs);
        if (why === "")
            return;
        sleepReleaseTimer.stop();
        root._lastSleep = Object.assign({}, root._lastSleep, { release: why, releasedAt: Date.now() });
        if (why === "failed" || why === "timeout")
            console.warn("LockService: letting suspend proceed without a lock:", why, root._sleepResult);
    }

    Timer {
        id: sleepReleaseTimer
        interval: 50
        repeat: true
        onTriggered: root._checkSleepRelease()
    }

    // gdbus rather than busctl: `busctl monitor` needs BecomeMonitor, which
    // the system bus grants root alone, while gdbus subscribes with a plain
    // match rule.
    Process {
        id: sleepMonitor
        command: Proc.dieWithParent(["gdbus", "monitor", "--system",
            "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"])
        running: root.beforeSleep
        stdout: SplitParser {
            onRead: line => {
                const sleeping = Lock.prepareForSleep(line);
                if (sleeping !== null)
                    root._onPrepareForSleep(sleeping);
            }
        }
        // A PrepareForSleep(false) sent while nothing was listening would
        // leave the inhibitor released for good.
        onRunningChanged: if (running) root._preparing = false
        onExited: exitCode => {
            if (root.beforeSleep)
                sleepMonitorRestart.restart();
        }
    }

    Timer {
        id: sleepMonitorRestart
        interval: 5000
        onTriggered: sleepMonitor.running = root.beforeSleep
    }

    // The inhibitor lives exactly as long as this child. `cat` on the
    // shell's stdin pipe is the thing held: stopping the Process, or the
    // shell dying, ends it and logind drops the lock with its fd.
    Process {
        id: sleepInhibitor
        command: Proc.dieWithParent(["systemd-inhibit", "--what=sleep", "--mode=delay",
            "--who=FormalShell", "--why=Lock the session before sleep", "cat"])
        stdinEnabled: true
        running: sleepMonitor.running && !(root._preparing && root._lastSleep !== null && root._lastSleep.release !== null)
    }
}
