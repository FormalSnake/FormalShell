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

    readonly property var _g: Geometry.frameGeometry(ring.width, ring.height,
        Theme.edgeInset, Theme.frameRadius)
    readonly property var _line: Geometry.strokeRect(ring._g.inner, ring._g.radius, Theme.borderWidth)

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
        // (DESIGN.md §3 Bar), half a stroke inside the band.
        ShapePath {
            id: line
            readonly property var i: ring._line
            readonly property real r: ring._line.radius
            fillColor: "transparent"
            strokeColor: Theme.color.border
            strokeWidth: Theme.borderWidth
            startX: line.i.x + line.r
            startY: line.i.y
            PathLine { x: line.i.x + line.i.width - line.r; y: line.i.y }
            PathArc { x: line.i.x + line.i.width; y: line.i.y + line.r; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.i.x + line.i.width; y: line.i.y + line.i.height - line.r }
            PathArc { x: line.i.x + line.i.width - line.r; y: line.i.y + line.i.height; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.i.x + line.r; y: line.i.y + line.i.height }
            PathArc { x: line.i.x; y: line.i.y + line.i.height - line.r; radiusX: line.r; radiusY: line.r }
            PathLine { x: line.i.x; y: line.i.y + line.r }
            PathArc { x: line.i.x + line.r; y: line.i.y; radiusX: line.r; radiusY: line.r }
        }
    }
}
