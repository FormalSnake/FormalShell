import QtQuick
import QtQuick.Shapes
import qs.Core
import "shoulders.js" as Outline

// The edge-anchored card's frame (DESIGN.md §2, M54 D6): `Card`'s fill,
// border and `radiusXl` corners on the three edges that face the desktop,
// the fourth edge open where it meets a line, and outside each of that
// edge's two corners a concave quarter fillet running out to the line. The
// line opens a gap of the card's length plus two fillets between its two
// segments (Surfaces/Bar/Bar.qml, Surfaces/Frame/FrameRing.qml), the
// fillets land in it, and the two windows read as one silhouette with the
// card growing out of the line.
//
// `edge` is the card's OWN anchored side, the one that meets the line, so a
// top bar hands its cards `edge: "top"`.
//
// The join lets go (2026-09-14): `attach` runs from 1, the card on the
// line with its fillets, to 0, a plain card with four rounded corners
// floating `nearInset` in from the item's line edge. In between the
// fillets shrink to sharp corners and round out the other way, the near
// edge moves in from the line, and its border, absent while the fill flows
// into the line, comes up with it. Joint.qml drives both off the card's
// travel.
//
// The fillets lie outside the card, which the consumer pays for in geometry:
// the item is `2 * overhang` longer than the card along the line and hangs
// half of that before it. Under a horizontal bar that is
// `x: cardX - shoulders.overhang; width: cardWidth + shoulders.overhang * 2`,
// beside a vertical one the same on y and height. `overhang` is `radius`
// alone and never reads the item's size, so binding the size to it is safe.
//
// The fill takes whatever opacity its colour carries, the way `Card` does:
// the caller passes `Theme.surface(...)` through, this file never applies an
// opacity of its own. `radius` 0 (the retro preset) draws square corners and
// no fillets at all, which is a plain card against a whole line.
Shape {
    id: root

    // "top" | "bottom" | "left" | "right"
    property string edge: "top"
    property real radius: Theme.radiusXl
    property color color: Theme.surface(Theme.color.card)
    property color borderColor: Theme.color.border
    property real borderWidth: Theme.borderWidth

    // 1 on the line, 0 floating free; see the header.
    property real attach: 1
    // Where the card's anchored edge sits, in from the item's line edge.
    property real nearInset: 0
    // A gap in the far edge's border, `[start, end]` along the item's own
    // bar axis, for a card coming out of THIS one the way this one comes
    // out of the bar (a tray item's menu off the tray's second bar). Null
    // for a whole edge.
    property var farGap: null

    readonly property real overhang: root.radius > 0 ? root.radius : 0

    readonly property real _attach: Math.max(0, Math.min(1, root.attach))
    // The near corners' one signed radius: the fillet at 1, sharp at 0.5,
    // the card's own rounding at 0.
    readonly property real _corner: root.radius * (2 * root._attach - 1)

    // Two paths off one construction: the fill on the card's own rect, the
    // stroke half a border in from it so a 1px line lands on one pixel row
    // rather than straddling two (Frame/geometry.js's strokeRect makes the
    // same half-stroke concession for the screen frame's ring).
    readonly property var _fill: Outline.outline(root.edge, root.width, root.height, root.radius, 0,
        root.nearInset, root._corner, null)
    readonly property var _line: Outline.outline(root.edge, root.width, root.height, root.radius,
        root.borderWidth / 2, root.nearInset, root._corner, root.farGap)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: fillPath
        readonly property var p: root._fill.p
        // A fillet sweeps against the free corners it joins: concave one
        // way, convex the other. Mirroring the canonical space onto a bottom
        // or left edge reverses both.
        readonly property int concave: root._fill.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._fill.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise
        readonly property int near: root._fill.nearConcave ? fillPath.concave : fillPath.convex

        fillColor: root.color
        strokeWidth: -1
        startX: fillPath.p[0].x
        startY: fillPath.p[0].y

        PathArc { x: fillPath.p[1].x; y: fillPath.p[1].y; radiusX: root._fill.nearRadius; radiusY: root._fill.nearRadius; direction: fillPath.near }
        PathLine { x: fillPath.p[2].x; y: fillPath.p[2].y }
        PathArc { x: fillPath.p[3].x; y: fillPath.p[3].y; radiusX: root._fill.convexRadius; radiusY: root._fill.convexRadius; direction: fillPath.convex }
        PathLine { x: fillPath.p[4].x; y: fillPath.p[4].y }
        PathArc { x: fillPath.p[5].x; y: fillPath.p[5].y; radiusX: root._fill.convexRadius; radiusY: root._fill.convexRadius; direction: fillPath.convex }
        PathLine { x: fillPath.p[6].x; y: fillPath.p[6].y }
        PathArc { x: fillPath.p[7].x; y: fillPath.p[7].y; radiusX: root._fill.nearRadius; radiusY: root._fill.nearRadius; direction: fillPath.near }
        // The near edge, closing the fill across the gap the line opened.
        // It is the one segment the outline stroke below leaves out.
        PathLine { x: fillPath.p[0].x; y: fillPath.p[0].y }
    }

    // The outline's stroke, in two runs so the far edge can open a gap
    // (`farGap`): the near corner, the near side and the far edge up to the
    // gap, then from the gap's other end round to the far near-corner.
    ShapePath {
        id: linePath
        readonly property var p: root._line.p
        readonly property int concave: root._line.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._line.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise
        readonly property int near: root._line.nearConcave ? linePath.concave : linePath.convex

        fillColor: "transparent"
        strokeColor: root.borderColor
        strokeWidth: root.borderWidth
        startX: linePath.p[0].x
        startY: linePath.p[0].y

        PathArc { x: linePath.p[1].x; y: linePath.p[1].y; radiusX: root._line.nearRadius; radiusY: root._line.nearRadius; direction: linePath.near }
        PathLine { x: linePath.p[2].x; y: linePath.p[2].y }
        PathArc { x: linePath.p[3].x; y: linePath.p[3].y; radiusX: root._line.convexRadius; radiusY: root._line.convexRadius; direction: linePath.convex }
        PathLine { x: root._line.g[0].x; y: root._line.g[0].y }
    }

    ShapePath {
        id: lineEndPath
        readonly property var p: root._line.p
        readonly property int convex: linePath.convex
        readonly property int near: linePath.near

        fillColor: "transparent"
        strokeColor: root.borderColor
        strokeWidth: root.borderWidth
        startX: root._line.g[1].x
        startY: root._line.g[1].y

        PathLine { x: lineEndPath.p[4].x; y: lineEndPath.p[4].y }
        PathArc { x: lineEndPath.p[5].x; y: lineEndPath.p[5].y; radiusX: root._line.convexRadius; radiusY: root._line.convexRadius; direction: lineEndPath.convex }
        PathLine { x: lineEndPath.p[6].x; y: lineEndPath.p[6].y }
        PathArc { x: lineEndPath.p[7].x; y: lineEndPath.p[7].y; radiusX: root._line.nearRadius; radiusY: root._line.nearRadius; direction: lineEndPath.near }
    }

    // The near edge's own border: nothing while the card is on the line,
    // where the fill runs straight into the bar, and the fourth side of a
    // card's frame once it has let go.
    ShapePath {
        id: nearPath
        readonly property var p: root._line.p

        fillColor: "transparent"
        strokeColor: Qt.alpha(root.borderColor, root.borderColor.a * (1 - root._attach))
        strokeWidth: root.borderWidth
        startX: nearPath.p[7].x
        startY: nearPath.p[7].y

        PathLine { x: nearPath.p[0].x; y: nearPath.p[0].y }
    }
}
