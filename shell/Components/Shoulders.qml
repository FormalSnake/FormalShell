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
// A side with no room for its fillet is walled (M57 D2, `wallStart` /
// `wallEnd`): attached, the silhouette runs out to the wall instead, taking
// the corner the wall's own line meets this card's in (`wallRadius`, square
// against a bare output edge) and carrying the near fillet turned a quarter
// against the wall past its own far edge. That side pulls back off
// the wall on the same attach clock, and its border, absent while the fill
// runs into the wall, comes up with the near edge's.
//
// The fillets lie outside the card, which the consumer pays for in geometry:
// the item is `2 * overhang` longer than the card along the line and hangs
// half of that before it. Under a horizontal bar that is
// `x: cardX - shoulders.overhang; width: cardWidth + shoulders.overhang * 2`,
// beside a vertical one the same on y and height. A walled side also grows
// the item by `farOverhang` past the card's far edge, for the fillet against
// the wall. Neither reads the item's size, so binding the size to them is
// safe.
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
    // How far past the card's own rect the silhouette runs to reach the wall
    // at either end of the line, -1 for a side with room for its fillet
    // (Joint.qml decides, off the card's resting rect). Both -1 for a
    // consumer that never walls.
    property real wallStart: -1
    property real wallEnd: -1
    // The radius the wall's own line and this card's meet in, for the corner
    // between them: a frame ring's rounded cut-out, 0 for the output's own
    // square edge (Components/Joint.qml decides, Drawer.qml measures the ring).
    property real wallRadius: 0
    // A gap in the far edge's border, `[start, end]` along the item's own
    // bar axis, for a card coming out of THIS one the way this one comes
    // out of the bar (a tray item's menu off the tray's second bar). Null
    // for a whole edge.
    property var farGap: null

    readonly property real overhang: Outline.overhang(root.radius, root.wallStart, root.wallEnd)
    readonly property real farOverhang: Outline.farOverhang(root.radius, root.wallStart, root.wallEnd)

    readonly property real _attach: Math.max(0, Math.min(1, root.attach))
    // The near corners' one signed radius: the fillet at 1, sharp at 0.5,
    // the card's own rounding at 0.
    readonly property real _corner: root.radius * (2 * root._attach - 1)
    readonly property var _walls: ({ start: root.wallStart, end: root.wallEnd,
        attach: root._attach, radius: root.wallRadius })

    // Two paths off one construction: the fill on the card's own rect, the
    // stroke half a border in from it so a 1px line lands on one pixel row
    // rather than straddling two (Frame/geometry.js's strokeRect makes the
    // same half-stroke concession for the screen frame's ring).
    //
    // While the card is attached the fill also starts one border in from the
    // item's line edge: that row belongs to the line's own window, which
    // paints it already, and a second translucent fill over it reads as a
    // seam across the whole gap. The lip goes with the attach clock, so a
    // card that has let go is its own rect again.
    readonly property var _fill: Outline.outline(root.edge, root.width, root.height, root.radius, 0,
        root.nearInset, root._corner, null, root.borderWidth * root._attach, root._walls)
    readonly property var _line: Outline.outline(root.edge, root.width, root.height, root.radius,
        root.borderWidth / 2, root.nearInset, root._corner, root.farGap, 0, root._walls)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: fillPath
        readonly property var p: root._fill.p
        readonly property var a: root._fill.arcs
        // A fillet sweeps against the free corners it joins: concave one
        // way, convex the other. Mirroring the canonical space onto a bottom
        // or left edge reverses both.
        readonly property int concave: root._fill.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._fill.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise

        function dir(k) { return fillPath.a[k].concave ? fillPath.concave : fillPath.convex; }

        fillColor: root.color
        strokeWidth: -1
        startX: fillPath.p[0].x
        startY: fillPath.p[0].y

        PathArc { x: fillPath.p[1].x; y: fillPath.p[1].y; radiusX: fillPath.a[0].r; radiusY: fillPath.a[0].r; direction: fillPath.dir(0) }
        PathLine { x: fillPath.p[2].x; y: fillPath.p[2].y }
        PathArc { x: fillPath.p[3].x; y: fillPath.p[3].y; radiusX: fillPath.a[1].r; radiusY: fillPath.a[1].r; direction: fillPath.dir(1) }
        PathLine { x: fillPath.p[4].x; y: fillPath.p[4].y }
        PathArc { x: fillPath.p[5].x; y: fillPath.p[5].y; radiusX: fillPath.a[2].r; radiusY: fillPath.a[2].r; direction: fillPath.dir(2) }
        PathLine { x: fillPath.p[6].x; y: fillPath.p[6].y }
        PathArc { x: fillPath.p[7].x; y: fillPath.p[7].y; radiusX: fillPath.a[3].r; radiusY: fillPath.a[3].r; direction: fillPath.dir(3) }
        // The near edge, closing the fill across the gap the line opened.
        // It is the one segment the outline stroke below leaves out.
        PathLine { x: fillPath.p[0].x; y: fillPath.p[0].y }
    }

    // The outline's stroke in three runs. Two of them carry the edges facing
    // the desktop, split so the far edge can open a gap (`farGap`): the
    // corner and side the traversal starts on, the far edge up to the gap,
    // then from the gap's other end round to where it ends. The third is
    // everything that runs into a line and so is absent while the card is
    // attached: the near edge always, and a walled side's own edge and its
    // corner on the line with it.
    //
    // Each run has a fixed shape whichever sides are walled, the elements
    // that belong to the other run collapsing onto one point and drawing
    // nothing: a walled side's edge moves out of the first two runs and into
    // the third, and the point list moves with it.
    readonly property bool _wStart: root._line.walled[0]
    readonly property bool _wEnd: root._line.walled[1]

    ShapePath {
        id: linePath
        readonly property var p: root._line.p
        readonly property var a: root._line.arcs
        readonly property int concave: root._line.mirrored ? PathArc.Counterclockwise : PathArc.Clockwise
        readonly property int convex: root._line.mirrored ? PathArc.Clockwise : PathArc.Counterclockwise

        function dir(k) { return linePath.a[k].concave ? linePath.concave : linePath.convex; }

        fillColor: "transparent"
        strokeColor: root.borderColor
        strokeWidth: root.borderWidth
        startX: (root._wStart ? linePath.p[2] : linePath.p[0]).x
        startY: (root._wStart ? linePath.p[2] : linePath.p[0]).y

        PathArc {
            x: (root._wStart ? linePath.p[2] : linePath.p[1]).x
            y: (root._wStart ? linePath.p[2] : linePath.p[1]).y
            radiusX: root._wStart ? 0 : linePath.a[0].r
            radiusY: root._wStart ? 0 : linePath.a[0].r
            direction: linePath.dir(0)
        }
        PathLine { x: linePath.p[2].x; y: linePath.p[2].y }
        PathArc { x: linePath.p[3].x; y: linePath.p[3].y; radiusX: linePath.a[1].r; radiusY: linePath.a[1].r; direction: linePath.dir(1) }
        PathLine { x: root._line.g[0].x; y: root._line.g[0].y }
    }

    ShapePath {
        id: lineEndPath
        readonly property var p: root._line.p
        readonly property var a: root._line.arcs

        function dir(k) { return linePath.dir(k); }

        fillColor: "transparent"
        strokeColor: root.borderColor
        strokeWidth: root.borderWidth
        startX: root._line.g[1].x
        startY: root._line.g[1].y

        PathLine { x: lineEndPath.p[4].x; y: lineEndPath.p[4].y }
        PathArc { x: lineEndPath.p[5].x; y: lineEndPath.p[5].y; radiusX: lineEndPath.a[2].r; radiusY: lineEndPath.a[2].r; direction: lineEndPath.dir(2) }
        PathLine {
            x: (root._wEnd ? lineEndPath.p[5] : lineEndPath.p[6]).x
            y: (root._wEnd ? lineEndPath.p[5] : lineEndPath.p[6]).y
        }
        PathArc {
            x: (root._wEnd ? lineEndPath.p[5] : lineEndPath.p[7]).x
            y: (root._wEnd ? lineEndPath.p[5] : lineEndPath.p[7]).y
            radiusX: root._wEnd ? 0 : lineEndPath.a[3].r
            radiusY: root._wEnd ? 0 : lineEndPath.a[3].r
            direction: lineEndPath.dir(3)
        }
    }

    // The near edge's own border, and a walled side's: nothing while the
    // card is on the line, where the fill runs straight into the bar and
    // into the wall, and the missing sides of a card's frame once it has
    // let go.
    ShapePath {
        id: nearPath
        readonly property var p: root._line.p
        readonly property var a: root._line.arcs

        function dir(k) { return linePath.dir(k); }

        fillColor: "transparent"
        strokeColor: Qt.alpha(root.borderColor, root.borderColor.a * (1 - root._attach))
        strokeWidth: root.borderWidth
        startX: (root._wEnd ? nearPath.p[5] : nearPath.p[7]).x
        startY: (root._wEnd ? nearPath.p[5] : nearPath.p[7]).y

        PathLine {
            x: (root._wEnd ? nearPath.p[6] : nearPath.p[7]).x
            y: (root._wEnd ? nearPath.p[6] : nearPath.p[7]).y
        }
        PathArc {
            x: nearPath.p[7].x
            y: nearPath.p[7].y
            radiusX: root._wEnd ? nearPath.a[3].r : 0
            radiusY: root._wEnd ? nearPath.a[3].r : 0
            direction: nearPath.dir(3)
        }
        PathLine { x: nearPath.p[0].x; y: nearPath.p[0].y }
        PathArc {
            x: (root._wStart ? nearPath.p[1] : nearPath.p[0]).x
            y: (root._wStart ? nearPath.p[1] : nearPath.p[0]).y
            radiusX: root._wStart ? nearPath.a[0].r : 0
            radiusY: root._wStart ? nearPath.a[0].r : 0
            direction: nearPath.dir(0)
        }
        PathLine {
            x: (root._wStart ? nearPath.p[2] : nearPath.p[0]).x
            y: (root._wStart ? nearPath.p[2] : nearPath.p[0]).y
        }
    }
}
