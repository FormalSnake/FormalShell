import QtQuick
import qs.Core
import "../Bar/layout.js" as BarLayout

// The modal scrim (spec "Depth", M57 D5): the `scrim` role, plain black at
// half opacity over the live desktop, drawn on the pose of the drawer it
// frames rather than on a clock of its own, so a scrim cannot drift out of
// step with the card it stands behind. It replaced a dithered freeze of the
// screen itself, which read beautifully in a still frame and could not be
// made to hold still in motion: refreshing it on an interval meant the
// capture contained the backdrop it was replacing, and every term in that
// loop drifted a little each generation, so the picture crawled while
// nothing on screen moved (owner, 2026-08-19). The lock screen still
// dithers, because its backdrop is one still wallpaper and never re-reads
// the screen.
//
// Two rectangles, not one: the band the card's own line belongs to
// (`Theme.edgeInset` on that edge, nothing at all on a bare edge) takes its
// share times `1 - attach`, so the card buds off a lit bar and the bar dims
// as the card lets go of it. The card is drawn over this, never through it:
// the compositor's `ignore_alpha` for the modal namespaces sits above the
// scrim's own alpha and below the card's, so what the scrim does to the
// desktop is darken it and what the card keeps is its blur
// (docs/examples/hyprland/formalshell.conf).
Item {
    id: root

    // The drawer whose card this stands behind: its edge, its pose and its
    // attach are the whole of what this is a function of.
    required property var drawer

    // The backdrop's own colour and how dark it goes, off the theme's table.
    // The alpha rides in the colour rather than on the item's opacity, which
    // the pose already owns: the two multiply out to the same pixel.
    readonly property color _tone: Theme.box("scrim").fill

    readonly property string _edge: root.drawer ? root.drawer.edge : "top"
    readonly property bool _vertical: BarLayout.isVertical(root._edge)
    readonly property real _inset: Theme.edgeInset[root._edge] || 0

    // The spatial pose overshoots 1 on the way in and dips under 0 on the way
    // out; an opacity may do neither.
    readonly property real _pose: root.drawer
        ? Math.max(0, Math.min(1, root.drawer.presence.pose)) : 0
    readonly property real _attach: root.drawer
        ? Math.max(0, Math.min(1, root.drawer.joint.attach)) : 0

    Rectangle {
        color: root._tone
        opacity: root._pose * (1 - root._attach)
        x: root._edge === "right" ? root.width - root._inset : 0
        y: root._edge === "bottom" ? root.height - root._inset : 0
        width: root._vertical ? root._inset : root.width
        height: root._vertical ? root.height : root._inset
    }

    Rectangle {
        color: root._tone
        opacity: root._pose
        x: root._edge === "left" ? root._inset : 0
        y: root._edge === "top" ? root._inset : 0
        width: root._vertical ? root.width - root._inset : root.width
        height: root._vertical ? root.height : root.height - root._inset
    }
}
