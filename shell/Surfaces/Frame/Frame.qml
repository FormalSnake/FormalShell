import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Core
import "../../Frame/geometry.js" as Geometry

// The screen frame (`frame.thickness` / `frame.radius`, off by default):
// the bar's `card` fill carried round the other three edges of the output
// as a band, with a rounded rectangle cut out of the whole for the desktop,
// so the bar reads as the thick side of one frame that wraps the screen
// and windows sit inside rounded corners. The look is Caelestia's border
// (modules/drawers, its BorderConfig), read as a reference; the drawing
// here is a Shape path with an even-odd fill, no shader and no C++.
//
// Two windows per edge role. The painter is one full-output layer surface
// that paints the whole ring, the bar's strip included, on the bottom
// layer: the bar keeps its cells, its input and its exclusive zone in its
// own window above and simply stops painting its fill, so the strip and
// the band are one surface under the compositor's blur. Two surfaces
// meeting edge to edge each blur and anti-alias their own boundary, and
// the join showed as a line down the strip (owner, 2026-08-26). It
// reserves nothing (`ExclusionMode.Ignore`) and takes no input at all: an
// empty `mask` builds an empty input region, the same click-through
// Tooltip.qml relies on. The three zones are 1px windows on the edges the
// bar is not on, each reserving the band's thickness, which is how a
// tiling compositor keeps windows inside the cut-out (Caelestia's
// Exclusions.qml does exactly this; a surface anchored on all four edges
// has no single edge to reserve against).
Scope {
    id: root
    required property var modelData

    readonly property bool _on: Theme.frameEnabled


    PanelWindow {
        id: painter
        screen: root.modelData
        visible: root._on
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region {}

        WlrLayershell.namespace: "formalshell:frame"
        // Bottom, so the bar's own window is always above it whatever the
        // two mapped in; nothing tiles over the band, since the zones
        // below reserve it.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        readonly property var _g: Geometry.frameGeometry(painter.width, painter.height,
            Theme.edgeInset, Theme.frameRadius)
        readonly property var _line: Geometry.strokeRect(painter._g.inner, painter._g.radius, Theme.borderWidth)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The ring: the output with the cut-out removed by the even-odd
            // rule (OddEvenFill, also the default).
            ShapePath {
                id: band
                readonly property var o: painter._g.outer
                readonly property var i: painter._g.inner
                readonly property real r: painter._g.radius
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
                readonly property var i: painter._line
                readonly property real r: painter._line.radius
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

    component Zone: PanelWindow {
        id: zone
        required property string edge
        screen: root.modelData
        visible: root._on && Theme.barPosition !== zone.edge
        anchors {
            top: zone.edge !== "bottom"
            bottom: zone.edge !== "top"
            left: zone.edge !== "right"
            right: zone.edge !== "left"
        }
        implicitWidth: 1
        implicitHeight: 1
        exclusiveZone: Theme.frameThickness
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "formalshell:frame-zone"
        // Overlay, deliberately: Hyprland arranges exclusive surfaces
        // background, bottom, top, overlay (IHyprRenderer::
        // arrangeLayersForMonitor), each one boxed by what the ones before
        // it left. The bar is on top; a zone on any lower layer would be
        // arranged first and take the two corners off the strip's ends
        // (observed in the VM: the strip configured 20px short). Arranged
        // after the bar, a zone reserves its band across what the strip
        // leaves, which is the geometry the painter draws. A 1px window
        // that paints nothing and takes no input is all the overlay layer
        // ever sees of it.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    Zone { edge: "top" }
    Zone { edge: "bottom" }
    Zone { edge: "left" }
    Zone { edge: "right" }
}
