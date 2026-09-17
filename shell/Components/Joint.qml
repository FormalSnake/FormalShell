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
// A card hanging off another panel rather than off the screen's own line
// (`target`) buds from what that panel's far edge can give: the silhouette's
// rect along the line is the card's clamped into the owner's span, widening
// to the card's own rect on the attach clock, and `clip` is the range the
// consumer holds the card to meanwhile.
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
    // The card's RESTING rect along the line, the output's own extent along
    // it, and what the line gives up at either end (Theme.edgeInset on the
    // two sides it runs between): what decides whether a side is walled
    // (M57 D2). The live rect is the wrong one to ask: a card mid-emerge or
    // mid-handoff would wall and unwall itself as it travels. Left at 0 by a
    // consumer that never walls (Surfaces/Notifications/Center.qml).
    property real restAlong: 0
    property real restLength: 0
    property real outputAlong: 0
    property real insetStart: 0
    property real insetEnd: 0
    // And the card's resting coordinate ACROSS the line, which is what puts
    // a walled side's own join on the wall in output coordinates.
    property real across: 0
    // Whose line: null for the screen's own (the bar's hairline, the frame
    // ring's), or the surface this card hangs off, which opens the gap in
    // its own far edge (Panel.qml's `owner`).
    property var target: null
    // And that surface's own rect along the line, live, with the corner
    // radius its far edge ends in: the span this card may bud from (M57 D3).
    // Live rather than resting, since a second bar goes on measuring its
    // cells after the open and the bud has to follow it frame by frame.
    property real targetAlong: 0
    property real targetLength: 0
    property real targetRadius: 0
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
    // presence is bypassed for a handoff (its pose then sits at 1), floats,
    // and so does one whose owner's edge is too short to bud from.
    property real attach: (root._joinable
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

    // --- Walls (M57 D2) --------------------------------------------------
    //
    // A side of the card resting closer than `radius` to where its line ends
    // has no room for its fillet, so while the card is attached the
    // silhouette runs out to that wall instead and pulls back off it on the
    // attach clock, exactly as the near edge pulls off the line by `neck`. A
    // card hanging off another panel is never walled: the span it may join
    // on is its owner's, not the screen's.
    readonly property bool _canWall: root._joinable && !root.target && root.radius > 0
        && root.outputAlong > 0 && root.restLength > 0

    readonly property real _roomStart: root.restAlong - root.insetStart
    readonly property real _roomEnd: root.outputAlong - root.insetEnd - root.restAlong - root.restLength

    // How far past its own rect the silhouette runs to reach the wall, or -1
    // for a side with room for its fillet.
    //
    // A line that ends at the output runs one radius past it, which is off
    // screen. A line that ends in a frame ring runs out to the ring's BAND,
    // one border past the ring's line: that line lies inside the cut-out,
    // over the desktop, where the bar's hairline lies over the strip's own
    // fill, so the row it gives up under a joined card is one nothing else
    // paints. The fill's lip then lands on exactly that row (M57 D1) instead
    // of stopping short of it and leaving a column of desktop between the
    // card and the band.
    readonly property real wallStart: (root._canWall && root._roomStart < root.radius)
        ? Math.max(0, root._roomStart) + (root.insetStart > 0 ? Theme.borderWidth : root.radius)
        : -1
    readonly property real wallEnd: (root._canWall && root._roomEnd < root.radius)
        ? Math.max(0, root._roomEnd) + (root.insetEnd > 0 ? Theme.borderWidth : root.radius)
        : -1

    // --- The nested bud (M57 D3) -----------------------------------------
    //
    // The span a card may join on: its owner's own far edge less the corner
    // radius that edge ends in, since the line stops where those corners
    // start, or, with no owner, the stretch of the screen's line between the
    // two insets. A card wider than its span joined with its whole rect, and
    // the card and both fillets hung out past either end of the strip they
    // were meant to bud from.
    //
    // A walled side is left alone: running out past its own rect to reach the
    // wall is exactly what D2 asks of it, and a card with an owner is never
    // walled, so the two rules never meet on one side.
    readonly property bool _spanned: root.target !== null && root.targetLength > 0
    readonly property bool _clampable: root._joinable
        && (root._spanned || root.outputAlong > 0)

    readonly property real _spanStart: root._spanned
        ? root.targetAlong + root.targetRadius
        : root.insetStart
    readonly property real _spanEnd: root._spanned
        ? root.targetAlong + root.targetLength - root.targetRadius
        : root.outputAlong - root.insetEnd
    readonly property real _spanLength: Math.max(0, root._spanEnd - root._spanStart)

    // A span with room for neither two fillets nor a sliver of card between
    // them is no line to bud from at all: the card comes out plain from under
    // the owner's edge instead, and `clip` holds it to the owner's span until
    // it is out, so nothing appears beside the owner either.
    readonly property bool _spanTight: root._spanned && root._spanLength < 4 * root.radius
    readonly property bool _joinable: root.joined && !root._spanTight

    // The card's rect along the line at full attach: pulled into the span
    // with room for a fillet at either end, so the silhouette, fillets and
    // all, is exactly the span.
    readonly property real _budStart: (root._clampable && root.wallStart < 0)
        ? Math.min(root.along + root.length, Math.max(root.along, root._spanStart + root.radius))
        : root.along
    readonly property real _budEnd: (root._clampable && root.wallEnd < 0)
        ? Math.max(root._budStart, Math.min(root.along + root.length, root._spanEnd - root.radius))
        : root.along + root.length

    readonly property bool _clamped: root._budStart > root.along
        || root._budEnd < root.along + root.length

    // And where it is right now: the bud attached, the card's own rect once
    // it has let go, widening between the two on the attach clock. What the
    // silhouette is drawn on, what the gap in the line is published from, and
    // what the consumer clips to, so the three cannot disagree.
    readonly property real clampedAlong: root.along
        + (root._budStart - root.along) * root._attach
    readonly property real clampedLength: Math.max(0, root.along + root.length
        + (root._budEnd - root.along - root.length) * root._attach - root.clampedAlong)

    // What the card may paint on along the line: the silhouette's own range,
    // fillets included, so the contents are revealed by the widening rather
    // than drawn outside the bud. They keep their full-width layout inside
    // it: clipped, never squeezed. Null once the rect is the card's own,
    // which is every card that is not budding.
    readonly property var clip: {
        if (!root.presence.shown)
            return null;
        if (root._spanTight)
            return root.slide > 0
                ? ({ start: root._spanStart, length: root._spanLength })
                : null;
        if (root._attach <= 0 || !root._clamped)
            return null;
        return ({
            start: root.clampedAlong - root.reach,
            length: root.clampedLength + root.reach * 2
        });
    }

    // Where the deform's pivot sits along the line, in the card's own
    // coordinates. A clamped bud takes its own middle: the matrix is centred
    // on the card's otherwise, which for a bud a fraction of the card's width
    // is far off to one side, and the squash then slides the whole bud along
    // the owner's gap. A walled card takes the wall it runs into, so the run
    // out to it stays ON it under the matrix, the way `pivotInset` keeps the
    // anchored edge on the line; without it the squash pulls the run-out off
    // the wall, which against a ring is a column of bare desktop. Null with
    // neither, and with a wall at either end, where there is no single side
    // to pin to.
    readonly property var alongPivot: (root._clamped && root._attach > 0)
        ? root.clampedAlong + root.clampedLength / 2 - root.along
        : ((root.wallStart >= 0) === (root.wallEnd >= 0)
            ? null
            : (root.wallStart >= 0 ? -root.wallStart : root.length + root.wallEnd))

    // The two edges the line runs between, which is where a walled side's
    // own join goes.
    readonly property string _startEdge: BarLayout.isVertical(root.edge) ? "top" : "left"
    readonly property string _endEdge: BarLayout.isVertical(root.edge) ? "bottom" : "right"

    // Which way the line lies from the card, and with it the card's own edge
    // on the line and the line's coordinate across it. `across` is the
    // card's near side on a top or left bar and its far one on a bottom or
    // right bar, since the rect is always given from its smaller corner.
    readonly property real _toLine: root._direction.x + root._direction.y
    readonly property real _nearEdge: root.across + (root._toLine > 0 ? root.extent : 0)
    readonly property real _lineAt: root._nearEdge + root._toLine * root.depth

    // The live extension on either side: the whole run out to the wall while
    // attached, nothing once the card has let go.
    readonly property real _outStart: root.wallStart >= 0 ? root.wallStart * root._attach : 0
    readonly property real _outEnd: root.wallEnd >= 0 ? root.wallEnd * root._attach : 0

    // Where the deform's pivot sits past the card's own edge: on the line
    // while attached, so the card squashes into the bar and the shoulders
    // stay on the line under the matrix, and on the card's edge once free.
    readonly property real pivotInset: (root.depth - root.slide) * root._attach

    // What the line opens: the silhouette's own rect along it, which is the
    // clamped rect widened by whatever a walled side runs out by, closing in
    // from both ends toward the centre as the card lets go, plus the
    // fillets' reach. The clamped rect and not the card's own, so an owner's
    // gap and the bud budding out of it land on the same two columns. Null
    // once the card floats, which is the line whole again. A reach running
    // past a wall is simply clamped by whoever draws the line
    // (Surfaces/Bar/Bar.qml, Frame/geometry.js's `ringLine`).
    readonly property real _joinStart: root.clampedAlong - root._outStart
    readonly property real _joinLength: root.clampedLength + root._outStart + root._outEnd

    readonly property var join: (root._joinable && root.presence.shown && root._attach > 0)
        ? ({
            edge: root.edge,
            x: root._joinStart + root._joinLength * (1 - root._attach) / 2,
            width: root._joinLength * root._attach,
            reach: root.reach,
            screen: root.screen,
            target: root.target
        })
        : null

    // And what a wall opens in its own line: the stretch of it the
    // silhouette covers, from the line the card came out of to the shape's
    // far edge, with the wall fillet's reach past that end. So a frame ring
    // gives way on the side the card runs into the way the bar gives way on
    // the side it comes out of.
    readonly property var wallJoins: {
        var out = [];
        if (!root.join)
            return out;
        var end = root._lineAt - root._toLine * root.shapeDepth;
        var start = Math.min(root._lineAt, end);
        for (var k = 0; k < 2; k++) {
            if ((k === 0 ? root.wallStart : root.wallEnd) < 0)
                continue;
            out.push({
                edge: k === 0 ? root._startEdge : root._endEdge,
                x: start,
                width: Math.abs(root.shapeDepth),
                reach: root.reach,
                screen: root.screen,
                target: null
            });
        }
        return out;
    }

    // Every join this drawer has open, published together: the registry
    // keys them by owner AND edge, so a side that stops being walled takes
    // its own entry down and leaves the others standing.
    readonly property var joins: root.join ? [root.join].concat(root.wallJoins) : []

    property var _published: []

    onJoinsChanged: {
        var live = [];
        var list = root.joins;
        for (var i = 0; i < list.length; i++) {
            PanelRegistry.setJoin(root.owner, list[i]);
            live.push(list[i].edge);
        }
        for (var k = 0; k < root._published.length; k++)
            if (live.indexOf(root._published[k]) < 0)
                PanelRegistry.clearJoin(root.owner, root._published[k]);
        root._published = live;
    }
}
