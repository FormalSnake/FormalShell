import QtQuick
import qs.Core

// The surface enter/exit recipe, in one place (DESIGN.md §1 "Motion"). Three
// modes, one clock discipline:
//
// - `fade` (M51 D2/D4, the default): fade, zoom from `motion.zoom` and a
//   `motion.slide` travel toward rest from the anchored edge, asymmetric in
//   and out (`motion.surface` to open, `motion.surfaceExit` to close) on the
//   enter easing both ways. Tooltips, the bar's own reveal, polkit and the
//   plugin overlay.
// - `emerge` (M53 addendum): the drawer. The card starts hidden behind the
//   edge it hangs off, displaced toward it by its own `extent` on that axis,
//   and travels to rest on `emphasized`. No fade and no zoom: the card's own
//   opacity stays 1 and the consumer's clip at the edge is what hides it, so
//   what arrives is a card coming out from under the bar rather than one
//   materialising in place. Its contents fade in behind the travel
//   (`contentOpacity`), so the card lands before its text.
// - `unfold` (M53 addendum): the launcher. The card is there almost at once
//   (`fast`) at whatever height the consumer seeds it with, and `morph`
//   carries it to full size on `emphasized` `easingInOut` with the contents
//   revealed under the growing edge.
//
// A summonable surface binds its own frame's opacity/scale/transformOrigin
// (and, where it wants the slide or the emerge, `transform: Translate {}`) to
// these read-outs instead of hand-rolling the Behavior and the
// opacity-triggered re-arm itself, and its window's `visible` binds to
// `shown`, replacing the `isOpen || frame.opacity > 0` copy every summonable
// surface used to spell out on its own.
//
// One Behavior per clock, not a SequentialAnimation: re-toggling `open`
// mid-flight retargets the same animation from wherever it is rather than
// restarting, so a fast re-open/re-close never stutters or snaps back to a
// stale pose. Everything derived below is a plain function of the two poses
// for the same reason: a read-out with a Behavior of its own would keep
// running after the pose it reads had already turned around.
QtObject {
    id: root

    property bool open: false
    // top/bottom/left/right anchors the zoom, the slide and the emerge to
    // that screen edge, the direction a closed surface sits displaced
    // toward. Anything else (the default, "center") is a modal surface:
    // zoom from the middle, no slide, no emerge.
    property string edge: "center"

    // "fade", "emerge" or "unfold"; see the header.
    property string mode: "fade"

    // `emerge` only: the card's own size on the anchored axis (its height
    // under a top or bottom bar, its width beside a vertical one), which is
    // how far behind the edge a closed card sits.
    property real extent: 0

    // Set while a surface is entering or leaving by some other means than
    // this recipe (Panel's handoff, M53 D5): every read-out below then lands
    // on the pose `open` names instead of on the transition toward it, so a
    // surface drawing its own trajectory has no fade, no zoom and no emerge
    // running under it, and an interruption part-way through finds the pose
    // at rest rather than a third of the way in. The progresses themselves
    // are left alone, so whatever they were doing has converged by the time
    // the bypass lifts.
    property bool bypass: false

    // Whether this surface's own window is really up. A summonable surface
    // maps its window on the tick it opens and the compositor can take a
    // sizeable fraction of the enter to put that surface on screen; an enter
    // started on `open` spends most of itself behind a window nobody can see
    // and lands on screen already at rest, which is a large part of why the
    // M51 recipe read as no animation at all on a real host (owner,
    // 2026-09-09). A consumer binds its own `backingWindowVisible` here and
    // the enter waits for it. The default is for a surface that is always
    // mapped and has nothing to wait for.
    property bool mapped: true

    // True while the surface is open but has nothing on screen yet: the pose
    // holds at rest closed rather than running behind an invisible window.
    readonly property bool _held: root.open && !root.mapped

    // True from the instant `open` flips true until the exit settles back to
    // 0. Both clocks count: a surface whose size is still folding back is
    // still on screen.
    readonly property bool shown: root.open || root._pose > 0
        || (root._twoClock && root._morphPose > 0)

    // Whether the size morph runs on a clock of its own. It does in `unfold`
    // alone: `emerge` puts the whole recipe on one clock, and `fade` has no
    // morph at all.
    readonly property bool _twoClock: root.mode === "unfold"

    property real _progress: (root.open && !root._held) ? 1 : 0
    Behavior on _progress {
        NumberAnimation {
            id: _progressAnimation
            // `emerge` runs the whole enter on the long clock, since the
            // travel IS the enter; `unfold` lands its card almost at once and
            // leaves the growth to the morph below.
            duration: {
                if (root.mode === "emerge")
                    return root.open ? Theme.motion.emphasized : Theme.motion.surface;
                if (root._twoClock)
                    return root.open ? Theme.motion.fast : Theme.motion.surfaceExit;
                return root.open ? Theme.motion.surface : Theme.motion.surfaceExit;
            }
            easing.type: Theme.motion.easing
        }
    }

    // `unfold`'s size clock: the travel curve on the long duration, which is
    // what every other size morph in the shell already rides (D2).
    property real _morphProgress: (root.open && !root._held) ? 1 : 0
    Behavior on _morphProgress {
        NumberAnimation {
            id: _morphAnimation
            duration: root.open ? Theme.motion.emphasized : Theme.motion.surface
            easing.type: Theme.motion.easingInOut
        }
    }

    // True once the animations above have actually reached their target,
    // false for as long as either is still carrying a pose there. `running`
    // flips the instant `open` changes (Behavior.start() is synchronous),
    // unlike the pose's own value, which only starts moving on the next
    // frame, so a consumer gating a size Behavior on this (DESIGN.md §1
    // Motion, M51 D5) never mistakes the first tick of a fresh transition for
    // rest.
    readonly property bool settled: root.bypass
        || (!root._held && !_progressAnimation.running
            && !(root._twoClock && _morphAnimation.running))

    // What every read-out below is a function of.
    readonly property real _pose: root.bypass ? (root.open ? 1 : 0) : root._progress
    readonly property real _morphPose: root.bypass ? (root.open ? 1 : 0) : root._morphProgress

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

    // 1 throughout in `emerge`: the card is hidden by the consumer's clip,
    // never by its own alpha, so nothing about it is see-through on the way
    // in (a translucent card fading over a translucent card is what made the
    // M51 open read as a flicker rather than as an arrival).
    readonly property real opacity: root.mode === "emerge" ? 1 : root._pose
    readonly property real scale: root.mode === "fade"
        ? Theme.motion.zoom + (1 - Theme.motion.zoom) * root._pose
        : 1
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
    // own. 0 on both axes for `edge: "center"`, and 0 in any mode but `fade`,
    // whose 8px nudge the emerge replaces outright.
    readonly property real slideX: root.mode === "fade"
        ? (1 - root._pose) * Theme.motion.slide * root._direction.x
        : 0
    readonly property real slideY: root.mode === "fade"
        ? (1 - root._pose) * Theme.motion.slide * root._direction.y
        : 0

    // The emerge's own travel, on the same convention: the whole `extent` at
    // rest closed, 0 open. The consumer applies it as a Translate and clips
    // at the edge, so a card at rest closed is entirely behind that line.
    readonly property real emergeX: root.mode === "emerge"
        ? (1 - root._pose) * root.extent * root._direction.x
        : 0
    readonly property real emergeY: root.mode === "emerge"
        ? (1 - root._pose) * root.extent * root._direction.y
        : 0

    // How far the size morph has come, for a consumer interpolating its own
    // geometry between a seed and its target (`unfold`'s card height).
    readonly property real morph: root._twoClock ? root._morphPose : root._pose

    // What the card's contents draw at while the card itself arrives: 0 until
    // the surface is a third of the way there, 1 at rest. A function of the
    // pose rather than a Behavior of its own, so a re-toggle mid-flight
    // reverses it with everything else instead of running on to a target
    // nothing is heading for any more.
    readonly property real contentOpacity: {
        if (root.mode === "fade")
            return 1;
        var p = root._twoClock ? root._morphPose : root._pose;
        return Math.max(0, Math.min(1, (p - 0.3) / 0.7));
    }
}
