.pragma library

// Where a tooltip card sits relative to the item that owns it (DESIGN.md §2
// "Tooltip", M44 D6). Pure, so tests can place a card against a screen
// without the Quickshell types Tooltip.qml pulls in, the same split
// cursor.js and Console/geometry.js already use.
//
// Every coordinate here is in the output's space. The tooltip is a
// full-screen layer surface, and every window that owns a tooltip-bearing
// item (the bar strip, a panel, the launcher, the notification centre)
// either spans its output or hugs one of its edges, so where it sits is
// known from its anchors alone (`windowOrigin`). Wayland hands clients no
// cross-window geometry to convert with, which is why that has to be
// derived rather than asked for.

var SIDES = ["below", "above", "right", "left"];

// Where a layer window's top-left corner sits on its output: 0 on any axis
// it is anchored to the start of or stretched across, and pushed to the far
// edge on an axis it is anchored only to the end of (a bar on the right or
// bottom edge). `anchors` is the window's own {top, bottom, left, right}.
function windowOrigin(anchors, size, screen) {
    return {
        x: anchors.right && !anchors.left ? screen.width - size.width : 0,
        y: anchors.bottom && !anchors.top ? screen.height - size.height : 0
    };
}

// Which side of a bar cell its tooltip goes: away from the bar's own edge,
// over the desktop. An item that is not on the bar (the default, an empty
// edge) takes "below".
function sideForBarEdge(barEdge) {
    switch (barEdge) {
    case "bottom": return "above";
    case "left": return "right";
    case "right": return "left";
    }
    return "below";
}

function _opposite(side) {
    switch (side) {
    case "below": return "above";
    case "above": return "below";
    case "right": return "left";
    }
    return "right";
}

function _fits(anchor, size, screen, gap, edge, side) {
    switch (side) {
    case "below": return anchor.y + anchor.height + gap + size.height + edge <= screen.height;
    case "above": return anchor.y - gap - size.height >= edge;
    case "right": return anchor.x + anchor.width + gap + size.width + edge <= screen.width;
    }
    return anchor.x - gap - size.width >= edge;
}

// On `side` of the anchor by default ("below" when not given); on the
// opposite side when the card would not fit there (a row at the bottom of a
// full-height surface). `edge` is the margin every floating surface keeps
// from the output's own edges, on both axes. `slideX`/`slideY` is the unit
// direction the card enters from, toward its anchor.
function placement(anchor, size, screen, gap, edge, side) {
    var preferred = SIDES.indexOf(side) >= 0 ? side : "below";
    var resolved = preferred;
    // A card too big for either side keeps its default side and clamps: an
    // off-output tooltip is worse than one that crowds its cell.
    if (!_fits(anchor, size, screen, gap, edge, preferred)
        && _fits(anchor, size, screen, gap, edge, _opposite(preferred)))
        resolved = _opposite(preferred);

    var lowestY = Math.max(edge, screen.height - size.height - edge);
    var rightmostX = Math.max(edge, screen.width - size.width - edge);
    var x;
    var y;
    switch (resolved) {
    case "below":
        y = anchor.y + anchor.height + gap;
        x = anchor.x + anchor.width / 2 - size.width / 2;
        break;
    case "above":
        y = anchor.y - gap - size.height;
        x = anchor.x + anchor.width / 2 - size.width / 2;
        break;
    case "right":
        x = anchor.x + anchor.width + gap;
        y = anchor.y + anchor.height / 2 - size.height / 2;
        break;
    default:
        x = anchor.x - gap - size.width;
        y = anchor.y + anchor.height / 2 - size.height / 2;
    }

    return {
        x: Math.max(edge, Math.min(x, rightmostX)),
        y: Math.max(edge, Math.min(y, lowestY)),
        side: resolved,
        slideX: resolved === "right" ? -1 : resolved === "left" ? 1 : 0,
        slideY: resolved === "below" ? -1 : resolved === "above" ? 1 : 0
    };
}
