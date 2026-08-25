import QtQuick
import qs.Core

// The mek.gallery dog-ear fold mark (DESIGN.md §2, item 7): one right
// triangle at a floating card's top-left corner, legs running along the
// top and left border edges, filled `mutedForeground`. Replaces the old
// four-square CornerMarks — a live-site scan found the corner squares
// gone; cards there carry a single folded-corner triangle instead. A
// Canvas repaints once per resize/color change (DitherFill precedent) —
// a clean hypotenuse isn't something a QML Rectangle can draw. Drop this
// as the last child of a card's frame Item (after its border Rectangles)
// so the mark paints on top; it takes its size from that parent via
// anchors.fill.
Item {
    id: root

    // lg-sized (8px at scale 1.0, DESIGN.md §2.7) — both legs run this far
    // from the corner point along the border edges they sit on.
    readonly property real markSize: Theme.space.lg
    readonly property color inkColor: Theme.color.mutedForeground

    anchors.fill: parent

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = root.inkColor;
            // Right angle at the corner point itself, one leg along the top
            // edge and one along the left edge — the fold mark sits flush
            // on the border ring the same way CornerMarks' squares did.
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(root.markSize, 0);
            ctx.lineTo(0, root.markSize);
            ctx.closePath();
            ctx.fill();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onInkColorChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
