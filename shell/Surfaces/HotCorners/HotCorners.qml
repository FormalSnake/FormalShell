import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core as Core
import qs.Services
import "../../HotCorners/corners.js" as Corners

// Pointer-driven corner triggers: throw the cursor into a screen corner and
// the shell locks or shows the screensaver. One controller (this Item)
// resolves the config, a Variants loop below spawns one tiny layer surface
// per active corner per output — the same "one controller, many surfaces"
// split Screensaver.qml uses, and for the same reason (Quickshell has no
// auto-multi-output primitive for a plain layer surface).
//
// Each surface is a `hotCorners.size` square of nothing: transparent, no
// content, no exclusive zone. Its input region is the whole (tiny) window,
// which is the one real cost here — Wayland has no hover-only input region,
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

    // Whether the action's own surface is already up. Two things read this:
    // the trigger itself (firing lock while locked is a no-op), and the
    // re-arming rule below, which needs to tell "the pointer left the corner"
    // from "our own action's surface took the pointer away from it".
    // A launcher action has no surface of its own to be already up, so it is
    // never active: it fires on every entry, and re-arms on the next leave
    // like any other corner.
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

                // Armed/disarmed rather than firing on every entry. Firing
                // maps the action's own surface above this one, which takes
                // the pointer with it — so dismissing that surface hands the
                // pointer straight back to a corner it never really left.
                // Re-arming only on a leave taken while the action is NOT
                // active is what stops that handoff from re-firing under a
                // parked cursor: leave the corner for real and it re-arms.
                property bool armed: true

                function fire() {
                    dwell.stop();
                    win.armed = false;
                    root.trigger(win.modelData.action);
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        if (win.armed && !root.actionActive(win.modelData.action))
                            dwell.restart();
                    }
                    onExited: {
                        dwell.stop();
                        if (!root.actionActive(win.modelData.action))
                            win.armed = true;
                    }
                    // This surface's input region eats the click whatever it
                    // does with it, so it fires outright rather than being
                    // lost — no dwell, a click on a 4px corner is deliberate.
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
