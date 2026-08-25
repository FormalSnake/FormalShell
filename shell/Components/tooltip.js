.pragma library

// Where a tooltip card sits relative to the item that owns it (DESIGN.md §2
// "Tooltip", M44 D6). Pure, so tests can place a card against a screen
// without the Quickshell types Tooltip.qml pulls in, the same split
// cursor.js and Console/geometry.js already use.
//
// Every coordinate here is in the anchor's own window space. The tooltip is
// a full-screen layer surface, and every window that owns a tooltip-bearing
// item (the bar strip, a panel, the launcher, the notification centre) is
// anchored at its output's top-left corner, so the two spaces coincide.
// Wayland hands clients no cross-window geometry to convert between them
// with, which is why that has to hold rather than be computed.
//
// Below the anchor by default; above it when the card would not fit under
// it (a row at the bottom of a full-height surface). `edge` is the margin
// every floating surface keeps from the output's own edges, on both axes.
function placement(anchor, size, screen, gap, edge) {
    var below = anchor.y + anchor.height + gap;
    var above = anchor.y - gap - size.height;
    var flipped = (below + size.height + edge > screen.height) && (above >= edge);

    // A card taller than the room on either side keeps its default side and
    // clamps: an off-output tooltip is worse than one that crowds its cell.
    var lowestY = Math.max(edge, screen.height - size.height - edge);
    var y = Math.max(edge, Math.min(flipped ? above : below, lowestY));

    var rightmostX = Math.max(edge, screen.width - size.width - edge);
    var x = Math.max(edge, Math.min(anchor.x + anchor.width / 2 - size.width / 2, rightmostX));

    return { x: x, y: y, above: flipped };
}
