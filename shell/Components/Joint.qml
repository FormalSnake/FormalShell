import QtQuick
import qs.Core
import "shoulders.js" as Outline
import "../Bar/layout.js" as BarLayout

// The join between a drawer and the line it comes out of (DESIGN.md §1
// Motion, 2026-09-14, the metamorphosis): a panel off the bar's hairline,
// the notification centre off the frame ring's far side. One of these sits
// beside a surface's `Presence` and turns the emerge into the numbers the
// surface's `Shoulders` draws by and the gap it publishes to the line.
//
// The card's contents travel with the frame, but the silhouette does not:
// it is drawn from the line to the card's far edge, so the fillets sit on
// the line from the first frame and what comes out is one shape budding off
// the strip, the way caelestia's popouts do. Once the card is nearly at rest
// (`releaseAt` of the pose, into the overshoot) it lets go: `attach` runs
// to 0 on its own clock while the card floats out to its resting place, the
// fillets shrinking to nothing and the corners rounding out, the near edge
// pulling off the line, and the line's gap closing in from both ends under
// the card. At rest the card is a plain `Card` a margin off the line, and
// the line is whole. Closing runs it all backwards: the card reattaches as
// it slides back under the line.
//
// Every read-out is a plain function of the presence's pose and the one
// attach clock, so a re-toggle mid-flight turns the whole join around from
// wherever it is.
QtObject {
    id: root

    // The surface, for the registry: a join is cleared by its owner alone.
    required property var owner
    required property Presence presence
    // The line's edge, the card's own anchored side.
    property string edge: "top"
    // Whether there is a line to meet at all. Off, this is a plain card:
    // `attach` pinned at 0, nothing published.
    property bool joined: true
    // From the card's resting edge to the line, the row of the line
    // included: what the shape reaches back by while attached.
    property real depth: 0
    property real radius: Theme.radiusXl
    // The card's live extent across the line (its height under a
    // horizontal bar), and its rect along the line in output coordinates.
    property real extent: 0
    property real along: 0
    property real length: 0
    property string screen: ""
    // Whose line: null for the screen's own (the bar's hairline, the frame
    // ring's), or the surface this card hangs off, which opens the gap in
    // its own far edge (Panel.qml's `owner`).
    property var target: null
    // The pose past which the card lets go of the line.
    property real releaseAt: 0.85

    readonly property var _direction: BarLayout.edgeVector(root.edge)

    // How far behind its rest the drawer is right now, toward the line:
    // the whole shape's extent closed, 0 at rest, a few pixels negative
    // while the spatial curve overshoots.
    readonly property real slide: root.presence.emergeX * root._direction.x
        + root.presence.emergeY * root._direction.y

    // How much of the shape is out from under the line: from the line to
    // the card's far edge, 0 while the card is wholly behind it. Past rest
    // it follows the overshoot outward with the line end pinned.
    readonly property real shapeDepth: Math.max(0, root.extent + root.depth - root.slide)

    // The room between the line and the card's own anchored edge: nothing
    // while that edge is still behind the line, `depth` at rest.
    readonly property real neck: Math.max(0, root.depth - root.slide)

    // 1 while the card is on the line, 0 once it has let go. 1 closed and
    // for the travel out, released as the pose passes `releaseAt`, on
    // `spatialFast` so the let-go overlaps the overshoot's return; a close
    // takes the pose back under the mark and the card reattaches on the
    // same clock as it slides in. A card with no line, or one whose
    // presence is bypassed for a handoff (its pose then sits at 1), floats.
    property real attach: (root.joined
        && !(root.presence.open && root.presence.morph >= root.releaseAt)) ? 1 : 0

    Behavior on attach {
        enabled: root.presence.shown
        Anim { kind: "spatialFast" }
    }

    readonly property real _attach: Math.max(0, Math.min(1, root.attach))

    // Where the card's anchored edge is drawn, in from the line: on it
    // while attached, its own `neck` off it once free.
    readonly property real nearInset: root.neck * (1 - root._attach)

    // How far the fillets run along the line outside the card's rect, for
    // the gap: their radius, capped at the shape's depth while it is still
    // shallow, and shrinking to nothing as the card lets go.
    readonly property real reach: Outline.filletRadius(root.radius * (2 * root._attach - 1),
        root.shapeDepth - root.nearInset)

    // Where the deform's pivot sits past the card's own edge: on the line
    // while attached, so the card squashes into the bar and the shoulders
    // stay on the line under the matrix, and on the card's edge once free.
    readonly property real pivotInset: (root.depth - root.slide) * root._attach

    // What the line opens: the card's rect along it, closing in from both
    // ends toward the centre as the card lets go, plus the fillets' reach.
    // Null once the card floats, which is the line whole again.
    readonly property var join: (root.joined && root.presence.shown && root._attach > 0)
        ? ({
            edge: root.edge,
            x: root.along + root.length * (1 - root._attach) / 2,
            width: root.length * root._attach,
            reach: root.reach,
            screen: root.screen,
            target: root.target
        })
        : null

    onJoinChanged: {
        if (root.join)
            PanelRegistry.setJoin(root.owner, root.join);
        else
            PanelRegistry.clearJoin(root.owner);
    }
}
