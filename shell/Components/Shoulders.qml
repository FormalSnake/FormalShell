import QtQuick
import QtQuick.Shapes
import qs.Core
import "shoulders.js" as Outline

// The edge-anchored card's frame (DESIGN.md §2, M54 D6): `Card`'s fill,
// border and `radiusXl` corners on the three edges that face the desktop,
// the fourth edge open where it meets the bar, and outside each of that
// edge's two corners a concave quarter fillet running out to the bar's own
// line. The bar opens a gap of the card's length plus two radii between its
// line's two segments (Surfaces/Bar/Bar.qml), the fillets land in it, and
// the two windows read as one silhouette with the card growing out of the
// line.
//
// `edge` is the card's OWN anchored side, the one that meets the bar, so a
// top bar hands its cards `edge: "top"`.
//
// The fillets lie outside the card, which the consumer pays for in geometry:
// the item is `2 * overhang` longer than the card along the bar and hangs
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

    readonly property real overhang: root.radius > 0 ? root.radius : 0

    // Two paths off one construction: the fill on the card's own rect, the
    // stroke half a border in from it so a 1px line lands on one pixel row
    // rather than straddling two (Frame/geometry.js's strokeRect makes the
    // same half-stroke concession for the screen frame's ring).
    readonly property var _fill: Outline.outline(root.edge, root.width, root.height, root.radius, 0)
    readonly property var _line: Outline.outline(root.edge, root.width, root.height, root.radius, root.borderWidth / 2)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: fillPath
        readonly property var p: root._fill.p
        // A fillet sweeps against the free corners it joins: concave one
        // way, convex the other. Mirroring the canonical space onto a bottom
        // or left edge reverses both.
        readonly property int concave: root._fill.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._fill.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise

        fillColor: root.color
        strokeWidth: -1
        startX: fillPath.p[0].x
        startY: fillPath.p[0].y

        PathArc { x: fillPath.p[1].x; y: fillPath.p[1].y; radiusX: root._fill.filletRadius; radiusY: root._fill.filletRadius; direction: fillPath.concave }
        PathLine { x: fillPath.p[2].x; y: fillPath.p[2].y }
        PathArc { x: fillPath.p[3].x; y: fillPath.p[3].y; radiusX: root._fill.convexRadius; radiusY: root._fill.convexRadius; direction: fillPath.convex }
        PathLine { x: fillPath.p[4].x; y: fillPath.p[4].y }
        PathArc { x: fillPath.p[5].x; y: fillPath.p[5].y; radiusX: root._fill.convexRadius; radiusY: root._fill.convexRadius; direction: fillPath.convex }
        PathLine { x: fillPath.p[6].x; y: fillPath.p[6].y }
        PathArc { x: fillPath.p[7].x; y: fillPath.p[7].y; radiusX: root._fill.filletRadius; radiusY: root._fill.filletRadius; direction: fillPath.concave }
        // The anchored edge, closing the fill across the gap the bar opened.
        // It is the one segment the stroke below leaves out.
        PathLine { x: fillPath.p[0].x; y: fillPath.p[0].y }
    }

    ShapePath {
        id: linePath
        readonly property var p: root._line.p
        readonly property int concave: root._line.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._line.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise

        fillColor: "transparent"
        strokeColor: root.borderColor
        strokeWidth: root.borderWidth
        startX: linePath.p[0].x
        startY: linePath.p[0].y

        PathArc { x: linePath.p[1].x; y: linePath.p[1].y; radiusX: root._line.filletRadius; radiusY: root._line.filletRadius; direction: linePath.concave }
        PathLine { x: linePath.p[2].x; y: linePath.p[2].y }
        PathArc { x: linePath.p[3].x; y: linePath.p[3].y; radiusX: root._line.convexRadius; radiusY: root._line.convexRadius; direction: linePath.convex }
        PathLine { x: linePath.p[4].x; y: linePath.p[4].y }
        PathArc { x: linePath.p[5].x; y: linePath.p[5].y; radiusX: root._line.convexRadius; radiusY: root._line.convexRadius; direction: linePath.convex }
        PathLine { x: linePath.p[6].x; y: linePath.p[6].y }
        PathArc { x: linePath.p[7].x; y: linePath.p[7].y; radiusX: root._line.filletRadius; radiusY: root._line.filletRadius; direction: linePath.concave }
    }
}
