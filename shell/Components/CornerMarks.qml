import QtQuick
import qs.Core

// The mek.gallery corner mark (DESIGN.md §2, item 7): a small square at each
// of a floating card's four border corners, centered on the border line,
// filled `foregroundFaint`. One shared component draws them — no surface
// hand-places its own geometry. Drop this as the last child of a card's
// frame Item (after its border Rectangles) so the marks paint on top; it
// takes its size from that parent via anchors.fill.
Item {
    id: root

    // xs-sized (3px at scale 1.0, DESIGN.md §2.7) — scales with
    // spacingScale against the 2px border the same way every other space
    // token does.
    readonly property real markSize: Theme.space.xs

    anchors.fill: parent

    Repeater {
        model: 4

        Rectangle {
            id: mark
            required property int index
            readonly property bool _top: index < 2
            readonly property bool _left: index % 2 === 0

            width: root.markSize
            height: root.markSize
            color: Theme.color.foregroundFaint
            // Centered on the corner point, straddling both border lines it
            // sits on — mek.gallery's own corner-mark placement.
            x: (mark._left ? 0 : root.width) - width / 2
            y: (mark._top ? 0 : root.height) - height / 2
        }
    }
}
