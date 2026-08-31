import QtQuick
import qs.Core

// The surface enter/exit recipe, in one place (DESIGN.md §1 "Motion", M51
// D2/D4): fade, zoom from `motion.zoom` and a `motion.slide` travel toward
// rest from the anchored edge, asymmetric in and out (`motion.surface` to
// open, `motion.surfaceExit` to close) on the enter easing both ways. A
// summonable surface binds its own frame's opacity/scale/transformOrigin
// (and, where it wants the slide, `transform: Translate { x: presence.slideX;
// y: presence.slideY }`) to these read-outs instead of hand-rolling the
// Behavior and the opacity-triggered re-arm itself, and its window's
// `visible` binds to `shown`, replacing the `isOpen || frame.opacity > 0`
// copy every summonable surface used to spell out on its own.
//
// One Behavior, not a SequentialAnimation: re-toggling `open` mid-flight
// retargets the same animation from wherever it is rather than restarting,
// so a fast re-open/re-close never stutters or snaps back to a stale pose.
QtObject {
    id: root

    property bool open: false
    // top/bottom/left/right anchors the zoom and the slide to that screen
    // edge, the direction a closed surface sits displaced toward. Anything
    // else (the default, "center") is a modal surface: zoom from the
    // middle, no slide.
    property string edge: "center"

    // True from the instant `open` flips true until the exit settles back
    // to `_progress` 0.
    readonly property bool shown: root.open || root._progress > 0

    property real _progress: root.open ? 1 : 0
    Behavior on _progress {
        NumberAnimation {
            id: _progressAnimation
            duration: root.open ? Theme.motion.surface : Theme.motion.surfaceExit
            easing.type: Theme.motion.easing
        }
    }

    // True once the animation above has actually reached its target, false
    // for as long as it's still carrying `_progress` there. `running` flips
    // the instant `open` changes (Behavior.start() is synchronous), unlike
    // `_progress`'s own value, which only starts moving on the next frame,
    // so a consumer gating a size Behavior on this (DESIGN.md §1 Motion,
    // M51 D5) never mistakes the first tick of a fresh transition for rest.
    readonly property bool settled: !_progressAnimation.running

    // Unit vector toward the anchored edge, the same convention
    // `shell/Bar/layout.js`'s edgeVector uses for the bar itself.
    readonly property point _direction: {
        switch (root.edge) {
        case "top": return Qt.point(0, -1);
        case "bottom": return Qt.point(0, 1);
        case "left": return Qt.point(-1, 0);
        case "right": return Qt.point(1, 0);
        default: return Qt.point(0, 0);
        }
    }

    readonly property real opacity: root._progress
    readonly property real scale: Theme.motion.zoom + (1 - Theme.motion.zoom) * root._progress
    readonly property int transformOrigin: {
        switch (root.edge) {
        case "top": return Item.Top;
        case "bottom": return Item.Bottom;
        case "left": return Item.Left;
        case "right": return Item.Right;
        default: return Item.Center;
        }
    }
    // The remaining distance toward the anchor: full `slide` at rest closed,
    // 0 once fully open, so a frame's own translate needs no Behavior of its
    // own. 0 on both axes for `edge: "center"`.
    readonly property real slideX: (1 - root._progress) * Theme.motion.slide * root._direction.x
    readonly property real slideY: (1 - root._progress) * Theme.motion.slide * root._direction.y
}
