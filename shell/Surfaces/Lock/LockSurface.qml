import QtQuick
import Quickshell.Wayland
import qs.Core
import qs.Core as Core
import qs.Components

// Per-output lock surface, instantiated automatically by WlSessionLock (see
// Lock.qml's `surface: Component { LockSurface { ... } }`) once for every
// screen, no manual Variants loop, unlike every other multi-output surface
// in this shell. The composed clock/date/field block itself lives in
// `qs.Components`' `AuthPrompt` (M8b Task 6), greeter.qml instantiates the
// exact same component as its own twin.
//
// Why this surface never captures the screen: a ScreencopyView + MultiEffect
// blurred-backdrop capture was tried first and
// crashes the lock screen outright (the moment ANY ScreencopyView exists,
// quickshell's WlBufferManager unconditionally negotiates v4+
// zwp_linux_dmabuf_v1 feedback with no version guard,
// src/wayland/buffer/dmabuf.cpp, and WlSessionLock::realizeLockTarget()
// constructs this surface, and fires captureFrame(), BEFORE calling
// manager->lock(), src/wayland/session_lock.cpp, so the protocol
// violation kills the whole Wayland connection, and thus the whole shell
// process, before the lock has actually engaged: a fail-OPEN crash on a
// security-critical surface). The backdrop below therefore reads a plain
// Image of `Core.State.wallpaper` (the same file Background.qml already
// shows on the desktop layer) and never the screen. Never reintroduce
// ScreencopyView here or anywhere lock-adjacent.
//
// That image draws plain under a 0.5 black scrim. `lock.dither` (default
// false, M45 D2) puts the retro dither pass back over it for anyone who
// wants it; nothing here has ever blurred, and DESIGN.md's one named blur
// exception is spent and gone.
//
// `Core.State` (qualified), not the bare `State` this file's other
// unqualified `import qs.Core` would suggest: QtQuick's own built-in `State`
// element (property-state-machine, exported by `import QtQuick`) shadows
// the unqualified singleton name, so a bare `State.wallpaper` silently reads
// `undefined` instead of erroring, reproduced via a Component.onCompleted
// console.warn that printed exactly `wallpaper=[undefined]`. Every other
// file that reads this singleton (`Background.qml`, `ThemeEngine.qml`)
// already imports `qs.Core as Core` for this exact reason; this file adds
// that same aliased import alongside its existing bare one rather than
// re-qualifying its own existing `Theme.*` references.
WlSessionLockSurface {
    id: surfaceRoot

    property string authError: ""
    property bool authenticating: false
    property bool fingerprintEnrolled: false
    // Idle-blanked (M7 Task 4, forwarded from Lock.qml's `blanked`): hides
    // the clock/backdrop/input entirely, leaving the plain background
    // Rectangle below, a real blank, not a dimmed clock, since the whole
    // point is nothing worth reading stays on screen while genuinely
    // unattended. Un-blanking flows from two places in Lock.qml: the
    // compositor's own IdleMonitor transition, and this surface's own
    // `activity` signal below (see its comment for why both are needed).
    property bool blanked: false
    // Fired on any real key or pointer activity reaching this surface.
    // IdleMonitor's own isIdle transition clears a resume-guard trip caused
    // by an organically-elapsed idle timeout just fine (isIdle was true,
    // input arrives, isIdle goes false, Lock.qml's onIsIdleChanged clears
    // it), but a resume-guard trip on its own can blank the surface while
    // isIdle is STILL false (the compositor's own idle timer is monotonic
    // and may not have elapsed at all yet), so isIdleChanged never fires to
    // clear it. This signal is the other half: real activity clears the
    // guard directly, regardless of what isIdle happens to be doing.
    signal activity()
    signal submit(string password)

    property date _now: new Date()

    readonly property bool _dither: Core.Config.get("lock.dither", false)

    // Matches every other top-layer surface's own opaque-frame precaution
    // (Panel.qml/Center.qml): WlSessionLockSurface.color's own doc warns
    // transparent backgrounds behave weirdly on some compositors, so this
    // stays solid at both the window and content level.
    color: Theme.color.background

    onVisibleChanged: {
        if (surfaceRoot.visible)
            Qt.callLater(function () { authPrompt.forceInputFocus(); });
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    // The wallpaper backdrop (spec "Lock and greeter"): plain by default,
    // and the source DitherImage samples when `lock.dither` is on. Hidden in
    // that case rather than removed, exactly as Background.qml hides its own
    // crossfade layers: a Canvas samples an invisible Image fine, and this
    // way the file decodes once either way. The solid Rectangle above is
    // what shows through when Core.State.wallpaper is unset.
    Image {
        id: wallpaperImage
        anchors.fill: parent
        visible: !surfaceRoot._dither && Core.State.wallpaper !== "" && !surfaceRoot.blanked
        source: Core.State.wallpaper !== "" ? "file://" + Core.State.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // Decode capped near the surface's own size (M16 Task 12), same
        // cover-vs-fit rationale as Background.qml's own wallpaper decode: a
        // square box sized to the larger screen side, not the straight
        // (width, height) box, so a non-screen-aspect wallpaper doesn't
        // decode short on one axis and get upscaled back out by the crop.
        sourceSize.width: Math.max(surfaceRoot.width, surfaceRoot.height)
        sourceSize.height: Math.max(surfaceRoot.width, surfaceRoot.height)
    }

    DitherImage {
        anchors.fill: parent
        mode: "retro"
        sourceItem: wallpaperImage
        visible: surfaceRoot._dither && Core.State.wallpaper !== "" && !surfaceRoot.blanked
        chunk: 8
        paletteSize: 6
    }

    // The modal scrim (spec "Depth"): plain black at half opacity, the same
    // one the launcher draws, so the column above reads against any
    // wallpaper. Hidden while blanked, where the point is that nothing at
    // all is on screen.
    Rectangle {
        anchors.fill: parent
        visible: Core.State.wallpaper !== "" && !surfaceRoot.blanked
        color: "black"
        opacity: 0.5
    }

    // Mouse-move activity detector for `activity()` (see its declaration
    // above): acceptedButtons Qt.NoButton means presses pass straight
    // through to whatever's beneath (the password cell's own MouseArea,
    // via TextInput's built-in one), this only ever tracks hover.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: surfaceRoot.activity()
    }

    AuthPrompt {
        id: authPrompt
        anchors.centerIn: parent
        visible: !surfaceRoot.blanked
        now: surfaceRoot._now
        errorText: surfaceRoot.authError
        checking: surfaceRoot.authenticating
        fingerprintEnrolled: surfaceRoot.fingerprintEnrolled
        onAccepted: password => surfaceRoot.submit(password)
        onActivity: surfaceRoot.activity()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: surfaceRoot._now = new Date()
    }
}
