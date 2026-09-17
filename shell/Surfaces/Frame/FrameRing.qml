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

    // The output this ring is on, for the joins it opens its line under.
    property string screenName: ""

    readonly property var _g: Geometry.frameGeometry(ring.width, ring.height,
        Theme.edgeInset, Theme.frameRadius)
    readonly property var _line: Geometry.strokeRect(ring._g.inner, ring._g.radius, Theme.borderWidth)

    // The span of the hairline a joined card's shoulders draw into, on any
    // side (PanelRegistry.joins, the card's rect plus its fillets' reach):
    // the same gap the unframed strip opens in its own line, cut here out
    // of the ring's, so a card hanging off a framed bar, or the
    // notification centre off the band opposite it, meets the line the way
    // a card meets a bare bar.
    function _gap(edge) {
        var j = PanelRegistry.joinOn(edge, ring.screenName);
        return j ? [j.x - j.reach, j.x + j.width + j.reach] : null;
    }

    readonly property var _strokes: Geometry.ringLine(ring._line, ring._line.radius, {
        top: ring._gap("top"),
        bottom: ring._gap("bottom"),
        left: ring._gap("left"),
        right: ring._gap("right")
    })

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
        // (DESIGN.md §3 Bar), half a stroke inside the band: each side in
        // two runs split at its gap, and the four corner arcs
        // (Frame/geometry.js's ringLine).
        Run { seg: ring._strokes.sides.top[0] }
        Run { seg: ring._strokes.sides.top[1] }
        Run { seg: ring._strokes.sides.right[0] }
        Run { seg: ring._strokes.sides.right[1] }
        Run { seg: ring._strokes.sides.bottom[0] }
        Run { seg: ring._strokes.sides.bottom[1] }
        Run { seg: ring._strokes.sides.left[0] }
        Run { seg: ring._strokes.sides.left[1] }
        Corner { seg: ring._strokes.corners[0] }
        Corner { seg: ring._strokes.corners[1] }
        Corner { seg: ring._strokes.corners[2] }
        Corner { seg: ring._strokes.corners[3] }
    }

    component Run: ShapePath {
        id: run
        required property var seg
        fillColor: "transparent"
        strokeColor: Theme.color.border
        strokeWidth: Theme.borderWidth
        startX: run.seg.x1
        startY: run.seg.y1
        PathLine { x: run.seg.x2; y: run.seg.y2 }
    }

    component Corner: ShapePath {
        id: corner
        required property var seg
        fillColor: "transparent"
        // Given up while a joined card's silhouette covers the arc
        // (Frame/geometry.js's `gone`): the card's own corner draws that
        // stretch of the cut-out's edge, and this one over it would be a line
        // across the card's fill.
        strokeColor: corner.seg.gone ? "transparent" : Theme.color.border
        strokeWidth: Theme.borderWidth
        startX: corner.seg.x1
        startY: corner.seg.y1
        PathArc { x: corner.seg.x2; y: corner.seg.y2; radiusX: ring._line.radius; radiusY: ring._line.radius }
    }
}
