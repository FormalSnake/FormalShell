import QtQuick
import qs.Core

// The ordered Bayer dither (DESIGN.md §2, item 8): a 2x2 checker of
// `mutedForeground` on transparent, the sanctioned "partial"/"pending"
// texture for a track's unfilled remainder, a pending notification row's
// backdrop, or a disabled toggle's field, replacing the low-alpha tint
// every one of those used to hand-roll. A Canvas repaints once per
// resize/color change, never per frame; a Repeater of individual cells was
// ruled out as too heavy for a texture painted this many times across the
// shell. `content` (optional) lets a caller stack something on top of the
// texture, the OSD/panel sliders drop their accent fill Rectangle in here
// so it still renders over the dither.
Item {
    id: root

    default property alias content: overlay.data
    property color inkColor: Theme.color.mutedForeground

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = root.inkColor;
            // 50% checker: every other pixel, alternating column parity by
            // row, so the pattern tiles seamlessly at a 2px period, the
            // flat 1-bit Macintosh/Amiga texture, never a smoothed wash.
            for (var y = 0; y < height; y++) {
                for (var x = y % 2; x < width; x += 2)
                    ctx.fillRect(x, y, 1, 1);
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onInkColorChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()

    Item {
        id: overlay
        anchors.fill: parent
    }
}
