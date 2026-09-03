import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Compositor
import qs.Core as Core
import qs.Services
import "../../HotCorners/corners.js" as Corners
import "../../HotCorners/arm.js" as Arm

// Pointer-driven corner triggers: throw the cursor into a screen corner and
// the shell locks or shows the screensaver. One controller (this Item)
// resolves the config, a Variants loop below spawns one tiny layer surface
// per active corner per output, the same "one controller, many surfaces"
// split Screensaver.qml uses, and for the same reason (Quickshell has no
// auto-multi-output primitive for a plain layer surface).
//
// Each surface is a `hotCorners.size` square of nothing: transparent, no
// content, no exclusive zone. Its input region is the whole (tiny) window,
// which is the one real cost here, Wayland has no hover-only input region,
// so those pixels stop reaching the window underneath. That is why the
// square is 4px by default and why a click on it fires the corner's action
// rather than being swallowed for nothing.
Item {
    id: root

    // Wired from shell.qml: null leaves the screensaver action inert rather
    // than erroring. Locking needs no handle, it goes through LockService
    // like every other lock trigger.
    property var screensaver: null
    // The launcher, for the corners carrying an action string. It owns the
    // shell's one action resolver (`@ipc:` dispatch and the spawn path), so
    // a corner reaches it rather than growing a second dispatch table that
    // would drift from the rows and the keybinds.
    property var menu: null

    readonly property var config: Corners.resolve(Core.Config.get("hotCorners", undefined))

    onConfigChanged: {
        for (var i = 0; i < root.config.warnings.length; i++)
            console.warn("HotCorners: " + root.config.warnings[i]);
    }

    // Raised when an action's own surface goes away, so the corner that
    // fired it can start its re-arm cooldown from the end rather than from
    // the fire. A signal on the controller rather than a read from each
    // window, because the Variants delegates below are not enumerable from
    // here.
    signal actionEnded(string action)

    // When each action last ended, by name. It lives here and not in the
    // window that fired, because the windows do not outlive an output list
    // or a config change: a screen waking or a settings.json save while the
    // session is locked rebuilds every one of them, and a corner that
    // adopted nothing would come up armed with the lock plate still on
    // screen. `Arm.adopt` reads it at construction.
    readonly property var endedAt: ({})

    function _actionEnded(action) {
        root.endedAt[action] = Date.now();
        root.actionEnded(action);
    }

    // Unlock is the only edge WlSessionLock reports: setLocked() emits
    // lockStateChanged() on its unlock path and nowhere else (Lock.qml's own
    // lock() comment has the C++ reading), which is exactly the edge wanted
    // here, so this handler needs no guard against a lock being mistaken for
    // an unlock. An external locker never gets this far, `lockScreen` is the
    // built-in surface or nothing.
    Connections {
        target: LockService.lockScreen
        ignoreUnknownSignals: true
        function onLockedChanged() {
            if (LockService.isLocked() === false)
                root._actionEnded("lock");
        }
    }

    Connections {
        target: root.screensaver
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (root.screensaver && !root.screensaver.active)
                root._actionEnded("screensaver");
        }
    }

    // Whether the action's own surface is already up. Two things read this:
    // the trigger itself (firing lock while locked is a no-op), and the
    // enter handler below, which will not start a dwell against a surface
    // that is already up.
    // A launcher action has no surface of its own to be already up, so it is
    // never active: it fires on every entry, and re-arms on a leave plus the
    // cooldown like any other corner.
    function actionActive(action) {
        // `isLocked` is null while an external locker owns the session
        // (LockService's header): unknown is not active, so a corner entry
        // still fires and the locker itself refuses a second instance.
        if (action === "lock")
            return LockService.isLocked() === true;
        if (action === "screensaver")
            return root.screensaver !== null && root.screensaver.active;
        return false;
    }

    function trigger(action) {
        if (root.actionActive(action))
            return;
        // An action that never reports back (a launcher string, an external
        // locker) is over as far as this shell can tell the moment it is
        // fired, so its cooldown starts here.
        if (!Arm.reportsEnd(action, LockService.external))
            root.endedAt[action] = Date.now();
        if (action === "lock")
            LockService.lock();
        else if (action === "screensaver" && root.screensaver)
            root.screensaver.start();
        else if (Corners.isLauncherAction(action) && root.menu)
            root.menu._runAction(action);
    }

    Variants {
        model: Corners.windows(root.config, Quickshell.screens)

        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                readonly property var edges: Corners.edges(win.modelData.corner)

                screen: win.modelData.screen
                // Down while a fullscreen window covers this output, both to
                // free its scanout and so a corner cannot fire mid-game.
                visible: !CompositorService.outputCoveredByFullscreen(win.modelData.screen.name)
                color: "transparent"

                WlrLayershell.namespace: "formalshell:hotcorner"
                // Top, not Overlay: the screensaver (Overlay) and the lock
                // surface both need to cover this one once fired, so that
                // their own dismiss/auth input reaches them across the whole
                // output, corners included.
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                // Two live anchors, never four: leaving the opposite edges
                // false is what makes the window take its size from
                // implicitWidth/implicitHeight instead of stretching across
                // the output.
                anchors.top: win.edges.top
                anchors.bottom: win.edges.bottom
                anchors.left: win.edges.left
                anchors.right: win.edges.right
                implicitWidth: root.config.size
                implicitHeight: root.config.size

                // Armed/disarmed rather than firing on every entry, and the
                // rules for it live in arm.js so they can be tested without a
                // compositor. The short of it: firing maps the action's own
                // surface above this one, which takes the pointer with it, so
                // dismissing that surface hands the pointer straight back to
                // a corner the cursor never really left. Re-arming wants both
                // a genuine leave and a quiet period after the action ends,
                // or the hand-back relocks the session the instant it is
                // unlocked. Not `state`: QtQuick exports its own State type
                // and the bare name reads back undefined.
                property var arm: Arm.initial()

                // Not a binding: this reads the controller once, at the
                // moment the surface is built, and everything after that is
                // driven by events.
                Component.onCompleted: win.arm = Arm.adopt(Date.now(),
                    root.actionActive(win.modelData.action),
                    root.endedAt[win.modelData.action] || 0)

                function fire() {
                    dwell.stop();
                    win.arm = Arm.onFire(win.arm, Date.now(),
                        Arm.reportsEnd(win.modelData.action, LockService.external));
                    root.trigger(win.modelData.action);
                }

                Connections {
                    target: root
                    function onActionEnded(action) {
                        if (action !== win.modelData.action)
                            return;
                        win.arm = Arm.onActionEnd(win.arm, Date.now(), hover.containsMouse);
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        const now = Date.now();
                        const armed = Arm.isArmed(win.arm, now);
                        win.arm = Arm.onEnter(win.arm, now);
                        if (armed && !root.actionActive(win.modelData.action))
                            dwell.restart();
                    }
                    onExited: {
                        dwell.stop();
                        win.arm = Arm.onExit(win.arm);
                    }
                    // This surface's input region eats the click whatever it
                    // does with it, so it fires outright rather than being
                    // lost, no dwell, a click on a 4px corner is deliberate.
                    // A button press is input the cooldown has nothing to say
                    // about: nothing hands a corner a click by accident.
                    onClicked: win.fire()
                }

                Timer {
                    id: dwell
                    interval: root.config.delayMs
                    repeat: false
                    onTriggered: win.fire()
                }
            }
        }
    }
}
