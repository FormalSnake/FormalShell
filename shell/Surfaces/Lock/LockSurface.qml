import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import qs.Core
import qs.Components

// Per-output lock surface, instantiated automatically by WlSessionLock (see
// Lock.qml's `surface: Component { LockSurface { ... } }`) once for every
// screen — no manual Variants loop, unlike every other multi-output surface
// in this shell. DESIGN.md's translation: "oversized clock (display slot),
// single bordered input cell."
//
// Blur: DESIGN.md's one exception in the whole shell. The API ground truth
// named BackgroundEffect.blurRegion for this, but it's QML_ATTACHED to a
// ProxyWindowBase (PanelWindow and friends) only — verified against
// background_effect/qml.cpp's qmlAttachedProperties(), which qobject_casts
// to ProxyWindowBase/WindowInterface and returns null otherwise.
// WlSessionLockSurface wraps its own raw QQuickWindow (session_lock.hpp) and
// is neither, so it cannot carry that attached property. MultiEffect
// (QtQuick.Effects, bundled in qtdeclarative since Qt 6.5 — no extra nix
// wiring beyond what quickshell already links against) blurs the
// ScreencopyView capture client-side instead: slower under the VM's
// llvmpipe software rasterizer, but it's the mechanism this surface type
// actually has.
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

    // Single-shot capture of whatever's on screen right before the lock
    // commits (WlSessionLock preloads surfaces before calling
    // manager->lock(), per session_lock.cpp) — a frozen backdrop, not a live
    // feed; a lock screen has no reason to keep re-capturing while shown.
    // captureSource only becomes valid once WlSessionLock assigns this
    // surface's screen (after Component construction, per
    // updateSurfaces()'s call order), so the frame is requested reactively
    // rather than from Component.onCompleted.
    //
    // Known environment gap, not a FormalShell bug: niri's winit (nested)
    // backend does not implement zwp_linux_dmabuf_v1 at all (niri-wm/niri
    // issue #2944) — the compositor advertises v3 while quickshell's own
    // WlBufferManager unconditionally negotiates v4+ dmabuf feedback the
    // moment ANY ScreencopyView is used, with no version guard, which the
    // server rejects as a protocol violation and kills the whole Wayland
    // connection (fatal, unrecoverable, un-catchable from QML — verified via
    // the exact wire error: "invalid version for zwp_linux_dmabuf_v1#N.
    // get_default_feedback (3, need at least 4)"). This only reproduces
    // nested (dev/smoke-niri.sh's own niri-in-niri test harness); real niri
    // on its TTY/DRM backend needs full dmabuf support for its own hardware
    // rendering and is not expected to hit this. `just vm-smoke --lock`
    // therefore cannot exercise the blurred backdrop specifically until
    // niri's winit backend gains the protocol or a real host is available;
    // every other part of this surface (clock, input cell, PAM round trip,
    // failed-auth inversion) is independently verified with this block
    // temporarily removed — see the M7 Task 3 verification notes. M7 Task 4
    // re-verified this same limitation still holds (the whole surface
    // crashes the instant `lock()` is called on this nested winit backend,
    // reproduced identically after adding idle blanking/fingerprint/error
    // states) and again verified every other part of this surface —
    // blanking, the wall-clock resume guard, the three-way uppercase error
    // split, the PAM round trip — with this block temporarily removed, then
    // restored the real code below and reconfirmed the exact same crash for
    // the record before committing.
    ScreencopyView {
        id: capture
        anchors.fill: parent
        captureSource: surfaceRoot.screen
        live: false
        visible: false
        onCaptureSourceChanged: if (capture.captureSource) capture.captureFrame()
    }

    MultiEffect {
        anchors.fill: capture
        source: capture
        visible: capture.hasContent && !surfaceRoot.blanked
        blurEnabled: true
        blur: 1.0
        blurMax: 64
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
