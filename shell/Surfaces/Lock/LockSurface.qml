import QtQuick
import Quickshell.Wayland
import qs.Core
import qs.Components

// Per-output lock surface, instantiated automatically by WlSessionLock (see
// Lock.qml's `surface: Component { LockSurface { ... } }`) once for every
// screen — no manual Variants loop, unlike every other multi-output surface
// in this shell. DESIGN.md's translation: "oversized clock (display slot),
// single bordered input cell."
//
// Blur: removed (was DESIGN.md's one exception in the whole shell — see
// docs/DESIGN.md and the spec for the now-stale carve-out language). A
// ScreencopyView + MultiEffect blurred-backdrop capture was built and
// verified to render, but it kills the lock screen outright: the moment ANY
// ScreencopyView is used, quickshell's WlBufferManager unconditionally
// negotiates v4+ zwp_linux_dmabuf_v1 feedback with no version guard
// (src/wayland/buffer/dmabuf.cpp), and WlSessionLock::realizeLockTarget()
// constructs this surface (and fires captureFrame()) BEFORE calling
// manager->lock() (src/wayland/session_lock.cpp) — so the protocol
// violation kills the whole Wayland connection, and thus the whole shell
// process, before the lock has actually engaged. That is a fail-OPEN crash
// on a security-critical surface: niri logs no "locking session" line at
// all, `lock isLocked` reports "No running instances", and the screen is
// never locked. Reproduced identically whether niri's dmabuf feedback
// negotiates v3 (nested winit backend, no DRM render node) — the fallback
// niri itself logs is "failed building default dmabuf feedback... error
// getting EGL device render node ... EGL_EXT_device_drm", a software-
// rendering property, not a nested-specific one, so a real host without a
// DRM render node is expected to hit the exact same crash. There is no
// QML-level guard available (the dmabuf negotiation is unconditional C++
// fired the instant a ScreencopyView exists, not deferred to
// captureFrame()), so the only fix that keeps lock() from crashing the
// shell is not using ScreencopyView at all. The backdrop is the plain solid
// Rectangle below.
WlSessionLockSurface {
    id: surfaceRoot

    property string authError: ""
    property bool authenticating: false
    // Idle-blanked (M7 Task 4, forwarded from Lock.qml's `blanked`): hides
    // the clock/backdrop/input entirely, leaving the plain background
    // Rectangle below — a real blank, not a dimmed clock, since the whole
    // point is nothing worth reading stays on screen while genuinely
    // unattended. Un-blanking flows from two places in Lock.qml: the
    // compositor's own IdleMonitor transition, and this surface's own
    // `activity` signal below (see its comment for why both are needed).
    property bool blanked: false
    // Fired on any real key or pointer activity reaching this surface.
    // IdleMonitor's own isIdle transition clears a resume-guard trip caused
    // by an organically-elapsed idle timeout just fine (isIdle was true,
    // input arrives, isIdle goes false, Lock.qml's onIsIdleChanged clears
    // it) — but a resume-guard trip on its own can blank the surface while
    // isIdle is STILL false (the compositor's own idle timer is monotonic
    // and may not have elapsed at all yet), so isIdleChanged never fires to
    // clear it. This signal is the other half: real activity clears the
    // guard directly, regardless of what isIdle happens to be doing.
    signal activity()
    signal submit(string password)

    property date _now: new Date()

    // Matches every other top-layer surface's own opaque-frame precaution
    // (Panel.qml/Center.qml): WlSessionLockSurface.color's own doc warns
    // transparent backgrounds behave weirdly on some compositors, so this
    // stays solid at both the window and content level.
    color: Theme.color.background

    onVisibleChanged: {
        if (surfaceRoot.visible)
            Qt.callLater(function () { passwordInput.forceActiveFocus(); });
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    // Mouse-move activity detector for `activity()` (see its declaration
    // above): acceptedButtons Qt.NoButton means presses pass straight
    // through to whatever's beneath (the password cell's own MouseArea,
    // via TextInput's built-in one) — this only ever tracks hover.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: surfaceRoot.activity()
    }

    Column {
        id: lockColumn
        anchors.centerIn: parent
        spacing: Theme.spacing.lg
        visible: !surfaceRoot.blanked

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(surfaceRoot._now, "hh:mm")
            color: Theme.color.foreground
            font.family: Theme.font.display
            font.pixelSize: 120
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(surfaceRoot._now, "dddd, MMMM d")
            color: Theme.color.foregroundDim
            font.family: Theme.font.family
            font.pixelSize: Theme.font.title
        }

        Cell {
            id: inputCell
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320
            selected: surfaceRoot.authError !== ""

            Column {
                id: pwColumn
                width: parent.width
                spacing: Theme.spacing.xs

                MetaLabel {
                    text: surfaceRoot.authError !== "" ? surfaceRoot.authError : "PASSWORD"
                }

                TextInput {
                    id: passwordInput
                    width: pwColumn.width
                    color: inputCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                    echoMode: TextInput.Password
                    focus: true
                    selectByMouse: true
                    cursorVisible: true

                    // Not accepted: this only reports activity alongside
                    // TextInput's own normal key handling, never instead of
                    // it.
                    Keys.onPressed: surfaceRoot.activity()

                    onAccepted: {
                        surfaceRoot.submit(passwordInput.text);
                        passwordInput.text = "";
                    }
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: surfaceRoot._now = new Date()
    }
}
