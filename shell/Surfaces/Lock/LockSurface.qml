import QtQuick
import Quickshell.Wayland
import qs.Core
import qs.Core as Core
import qs.Components
import qs.Theme as Paint
import "../../Lock/model.js" as Model

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
// That image draws plain under a 0.5 black scrim on the metamorphosis preset.
// `lock.dither` (M45 D2, defaulting to `theme.dither`, which the preset
// sets) puts the retro dither pass back over it; nothing here has ever
// blurred, and DESIGN.md's one named blur exception is spent and gone.
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
    // Idle-blanked (M7 Task 4, forwarded from Lock.qml's `blanked`): takes
    // the clock/backdrop/input off entirely, leaving the plain background
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
    // What this output decided, for `lock status` (Lock.qml's `outputs`).
    signal report(string name, var state)

    property date _now: new Date()

    readonly property bool _dither: Core.Theme.lockDither

    // The scrim's opacity over the wallpaper, and so how dark whatever the
    // words sit on is. The ink below is chosen against that composite.
    readonly property real _scrimAlpha: 0.5
    readonly property bool _hasWallpaper: Core.State.wallpaper !== ""

    // The ink of the words on the wallpaper, by contrast with what is under
    // them rather than by the palette's mode (Lock/model.js's `ink`): the
    // clock block and the now-playing block each read their own rect of the
    // wallpaper through the bar's sampler, never the screen. Without a
    // wallpaper they sit on the flat background, and while a wallpaper has
    // not been read yet the scrim is the best guess at what is under them,
    // which is dark.
    readonly property real _fallbackLuma: surfaceRoot._hasWallpaper ? 0
        : Model.lumaOf(Theme.color.background.r, Theme.color.background.g, Theme.color.background.b)
    readonly property string _clockInk: Model.ink(clockSampler.stats,
        surfaceRoot._hasWallpaper ? surfaceRoot._scrimAlpha : 0, surfaceRoot._fallbackLuma)
    readonly property string _mediaInk: Model.ink(mediaSampler.stats,
        surfaceRoot._hasWallpaper ? surfaceRoot._scrimAlpha : 0, surfaceRoot._fallbackLuma)
    readonly property var _clockBox: Theme.box("lock.ink", surfaceRoot._clockInk)
    readonly property var _mediaBox: Theme.box("lock.ink", surfaceRoot._mediaInk)

    // Where the transport cursor sits, -1 while it is off and the field's
    // keys are all the field's (Lock/model.js's `transportKey`).
    property int _transportCursor: -1

    function _keyName(event) {
        switch (event.key) {
        case Qt.Key_Tab: return "tab";
        case Qt.Key_Backtab: return "backtab";
        case Qt.Key_Left: return "left";
        case Qt.Key_Right: return "right";
        case Qt.Key_Return:
        case Qt.Key_Enter: return "enter";
        case Qt.Key_Escape: return "escape";
        case Qt.Key_Shift:
        case Qt.Key_Control:
        case Qt.Key_Alt:
        case Qt.Key_AltGr:
        case Qt.Key_Meta:
        case Qt.Key_Super_L:
        case Qt.Key_Super_R:
        case Qt.Key_CapsLock: return "modifier";
        default: return "other";
        }
    }

    function _filterKey(event) {
        var step = Model.transportKey(surfaceRoot._transportCursor, nowPlaying.transport.length,
            surfaceRoot._keyName(event));
        surfaceRoot._transportCursor = step.index;
        if (step.press)
            nowPlaying.press(step.index);
        if (step.taken)
            event.accepted = true;
    }

    readonly property string _outputName: surfaceRoot.screen ? surfaceRoot.screen.name : ""
    readonly property var _reportState: ({
        clockInk: surfaceRoot._clockInk,
        clockLuma: Model.backdropLuma(clockSampler.stats,
            surfaceRoot._hasWallpaper ? surfaceRoot._scrimAlpha : 0, surfaceRoot._fallbackLuma),
        clockSampled: clockSampler.stats.sampled,
        clockRect: {
            x: clockSampler.region.x,
            y: clockSampler.region.y,
            width: clockSampler.region.width,
            height: clockSampler.region.height
        },
        mediaInk: surfaceRoot._mediaInk,
        mediaLuma: Model.backdropLuma(mediaSampler.stats,
            surfaceRoot._hasWallpaper ? surfaceRoot._scrimAlpha : 0, surfaceRoot._fallbackLuma),
        nowPlaying: nowPlaying.shown,
        transportCursor: surfaceRoot._transportCursor
    })
    // Held until the surface knows its output: a report under "" would sit
    // beside the real one for the rest of the lock.
    on_ReportStateChanged: {
        if (surfaceRoot._outputName !== "")
            surfaceRoot.report(surfaceRoot._outputName, surfaceRoot._reportState);
    }

    // The content column's entrance (M51 Task 7): opacity 0 to 1 plus an
    // upward rise, played once when this surface is created. A Behavior
    // never fires on a property's own initial value, only on a later
    // change, so the trigger is an explicit NumberAnimation restarted from
    // Component.onCompleted below, the same one-shot idiom Menu.qml's level
    // entrance uses. Enter only: unlock releases the session lock and this
    // whole surface is destroyed, nothing left to animate against, and
    // neither property gates focus, PAM or key handling, both default to
    // their settled values so the column reads and accepts input from the
    // first frame regardless of where the animation is.
    property real _contentOpacity: 1
    property real _contentRise: 0

    // Idle blank and wake (M53 Task 7): everything above the plain
    // background Rectangle crosses to and from 0 on `reveal`, the same clock
    // the wallpaper crossfade and the screensaver's own fade already use,
    // since a full-screen swap paced at the length of a hover wash reads as
    // a flash. Nothing here gates input: the field keeps its focus and its
    // key handling through the fade, so the keystroke that woke the surface
    // is also the first character of the password. `motion.enabled: false`
    // zeroes `reveal` too, so a reduced-motion session still gets the hard
    // cut.
    property real _wakeOpacity: surfaceRoot.blanked ? 0 : 1

    Behavior on _wakeOpacity {
        Anim { kind: "reveal" }
    }

    // Mapped from the instant the blank lifts, not from the instant the fade
    // reaches a pixel: the wake has to accept the key that caused it.
    readonly property bool _wakeShown: !surfaceRoot.blanked || surfaceRoot._wakeOpacity > 0

    // Matches every other top-layer surface's own opaque-frame precaution
    // (Panel.qml/Center.qml): WlSessionLockSurface.color's own doc warns
    // transparent backgrounds behave weirdly on some compositors, so this
    // stays solid at both the window and content level.
    color: Theme.color.background

    onVisibleChanged: {
        if (surfaceRoot.visible)
            Qt.callLater(function () { authPrompt.forceInputFocus(); });
    }

    Component.onCompleted: {
        contentEnterOpacity.restart();
        contentEnterRise.restart();
    }

    // The entrance, as two terms rather than one (M54 D2): the fade is not
    // geometry and must not overshoot, the rise is and does.
    Anim {
        id: contentEnterOpacity
        kind: "effects"
        target: surfaceRoot
        property: "_contentOpacity"
        from: 0
        to: 1
    }

    // How far the card comes up. A distance, so it takes the spacing scale
    // rather than a literal: the same number on a 2x scale would read as
    // half the travel.
    readonly property real _contentRiseFrom: Theme.space.sectionGap

    Anim {
        id: contentEnterRise
        target: surfaceRoot
        property: "_contentRise"
        from: surfaceRoot._contentRiseFrom
        to: 0
    }

    // Black while blanked, whatever the mode: a light theme's background is
    // near white, which is a lit screen rather than a blank one.
    Rectangle {
        anchors.fill: parent
        color: surfaceRoot._wakeShown ? Theme.color.background : "black"
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
        visible: !surfaceRoot._dither && Core.State.wallpaper !== "" && surfaceRoot._wakeShown
        // Held at 1 while the dither pass is the visible one: that pass
        // samples this item, so an opacity here would reach its texture and
        // fade the source out from under it. The pass carries the fade
        // itself in that case.
        opacity: surfaceRoot._dither ? 1 : surfaceRoot._wakeOpacity
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
        visible: surfaceRoot._dither && Core.State.wallpaper !== "" && surfaceRoot._wakeShown
        opacity: surfaceRoot._wakeOpacity
        chunk: 8
        paletteSize: 6
    }

    // The modal scrim (spec "Depth"): plain black at half opacity, the same
    // one the launcher draws, so the column above reads against any
    // wallpaper. Gone while blanked, where the point is that nothing at
    // all is on screen.
    Rectangle {
        anchors.fill: parent
        visible: Core.State.wallpaper !== "" && surfaceRoot._wakeShown
        color: "black"
        opacity: 0.5 * surfaceRoot._wakeOpacity
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
        visible: surfaceRoot._wakeShown
        opacity: surfaceRoot._contentOpacity * surfaceRoot._wakeOpacity
        transform: Translate { y: surfaceRoot._contentRise }
        now: surfaceRoot._now
        errorText: surfaceRoot.authError
        checking: surfaceRoot.authenticating
        fingerprintEnrolled: surfaceRoot.fingerprintEnrolled
        avatarPath: Core.Config.avatarPath
        ink: surfaceRoot._clockBox.ink
        dateInk: surfaceRoot._clockBox.ink
        inkShadow: surfaceRoot._clockBox.inkShadow
        onAccepted: password => surfaceRoot.submit(password)
        onActivity: surfaceRoot.activity()
        onKeyFilter: event => surfaceRoot._filterKey(event)
    }

    LockNowPlaying {
        id: nowPlaying
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: authPrompt.bottom
        anchors.topMargin: Theme.space.sectionGap * 2
        width: implicitWidth
        height: implicitHeight
        visible: nowPlaying.shown && surfaceRoot._wakeShown
        opacity: surfaceRoot._contentOpacity * surfaceRoot._wakeOpacity
        transform: Translate { y: surfaceRoot._contentRise }
        ink: surfaceRoot._mediaBox.ink
        subInk: surfaceRoot._mediaBox.ink
        inkShadow: surfaceRoot._mediaBox.inkShadow
        cursorIndex: surfaceRoot._transportCursor
        onPressed: authPrompt.forceInputFocus()
        onShownChanged: if (!nowPlaying.shown) surfaceRoot._transportCursor = -1
    }

    // The two samplers behind the ink, each over its own block's resting
    // rect (the entrance's rise is left out: it is gone within a clock).
    Paint.BarPaint {
        id: clockSampler
        source: surfaceRoot._hasWallpaper ? "file://" + Core.State.wallpaper : ""
        screenSize: Qt.size(surfaceRoot.width, surfaceRoot.height)
        region: Qt.rect(authPrompt.x + authPrompt.inkRect.x, authPrompt.y + authPrompt.inkRect.y,
            authPrompt.inkRect.width, authPrompt.inkRect.height)
    }

    Paint.BarPaint {
        id: mediaSampler
        source: surfaceRoot._hasWallpaper ? "file://" + Core.State.wallpaper : ""
        screenSize: Qt.size(surfaceRoot.width, surfaceRoot.height)
        region: Qt.rect(nowPlaying.x, nowPlaying.y, nowPlaying.width, nowPlaying.height)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: surfaceRoot._now = new Date()
    }
}
