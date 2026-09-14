import QtQuick
import QtQuick.Shapes
import qs.Core
import "../../Frame/geometry.js" as Geometry

// The screen frame's ring (`frame.thickness` / `frame.radius`, off by
// default): the bar's `card` fill carried round the other three edges of
// the output as a band, with a rounded rectangle cut out of the whole for
// the desktop, so the bar reads as the thick side of one frame that wraps
// the screen and windows sit inside rounded corners. The look is
// Caelestia's border (modules/drawers, its BorderConfig), read as a
// reference; the drawing here is a Shape path with an even-odd fill, no
// shader and no C++. Bar.qml hosts one, filling its window while that
// window is the whole output; the ring paints the strip too, and the bar's
// cells draw over it.
Item {
    id: ring

    // The bar's side, and the span of the hairline on it a joined card's
    // shoulders draw into (Bar.qml's `_gapStart`/`_gapEnd`, in this
    // window's coordinates along that side): the same gap the unframed
    // strip opens in its own line, cut here out of the ring's, so a card
    // hanging off a framed bar meets the line the way it meets a bare one.
    property string edge: "top"
    property real gapStart: 0
    property real gapEnd: 0

    readonly property var _g: Geometry.frameGeometry(ring.width, ring.height,
        Theme.edgeInset, Theme.frameRadius)
    readonly property var _line: Geometry.strokeRect(ring._g.inner, ring._g.radius, Theme.borderWidth)
    readonly property var _walk: Geometry.lineWalk(ring._line, ring._line.radius, ring.edge,
        ring.gapStart, ring.gapEnd)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The ring: the output with the cut-out removed by the even-odd
        // rule (OddEvenFill, also the default).
        ShapePath {
            id: band
            readonly property var o: ring._g.outer
            readonly property var i: ring._g.inner
            readonly property real r: ring._g.radius
            fillRule: ShapePath.OddEvenFill
            fillColor: Theme.surface(Theme.color.card)
            strokeWidth: -1
            startX: band.o.x
            startY: band.o.y
            PathLine { x: band.o.x + band.o.width; y: band.o.y }
            PathLine { x: band.o.x + band.o.width; y: band.o.y + band.o.height }
            PathLine { x: band.o.x; y: band.o.y + band.o.height }
            PathLine { x: band.o.x; y: band.o.y }
            PathMove { x: band.i.x + band.r; y: band.i.y }
            PathLine { x: band.i.x + band.i.width - band.r; y: band.i.y }
            PathArc { x: band.i.x + band.i.width; y: band.i.y + band.r; radiusX: band.r; radiusY: band.r }
            PathLine { x: band.i.x + band.i.width; y: band.i.y + band.i.height - band.r }
            PathArc { x: band.i.x + band.i.width - band.r; y: band.i.y + band.i.height; radiusX: band.r; radiusY: band.r }
            PathLine { x: band.i.x + band.r; y: band.i.y + band.i.height }
            PathArc { x: band.i.x; y: band.i.y + band.i.height - band.r; radiusX: band.r; radiusY: band.r }
            PathLine { x: band.i.x; y: band.i.y + band.r }
            PathArc { x: band.i.x + band.r; y: band.i.y; radiusX: band.r; radiusY: band.r }
        }

        // The hairline along the cut-out, the one edge the frame draws
        // (DESIGN.md §3 Bar), half a stroke inside the band: one open walk
        // round it, clockwise from one end of the gap on the bar's side to
        // the other (Frame/geometry.js's lineWalk), which with no gap is
        // the whole ring.
        ShapePath {
            id: line
            readonly property var p: ring._walk
            readonly property real r: ring._line.radius
            fillColor: "transparent"
            strokeColor: Theme.color.border
            strokeWidth: Theme.borderWidth
            startX: line.p[0].x
            startY: line.p[0].y
            PathLine { x: line.p[1].x; y: line.p[1].y }
            PathArc { x: line.p[2].x; y: line.p[2].y; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.p[3].x; y: line.p[3].y }
            PathArc { x: line.p[4].x; y: line.p[4].y; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.p[5].x; y: line.p[5].y }
            PathArc { x: line.p[6].x; y: line.p[6].y; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.p[7].x; y: line.p[7].y }
            PathArc { x: line.p[8].x; y: line.p[8].y; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.p[9].x; y: line.p[9].y }
        }
    }
}
