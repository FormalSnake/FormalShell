.pragma library

// Drawer.qml's geometry, as pure functions (the same split
// Components/geometry.js and Frame/geometry.js already use): where the line
// a card comes out of lies, how deep the shape reaches back to it, and the
// band the card may paint in.
//
// A consumer states the edge it comes out of and its resting rect; every
// number below follows from those, the output and `Theme.edgeInset`, so a
// surface that moves, resizes or changes edge at runtime is followed without
// being told.

function vertical(edge) {
    return edge === "left" || edge === "right";
}

// Which way the line lies from the card: +1 for one at the far end of the
// across axis (a bottom bar, the output's right edge), -1 for one at its
// origin.
function toLine(edge) {
    return (edge === "bottom" || edge === "right") ? 1 : -1;
}

// The card's own anchored side, the one that faces the line.
function nearEdge(edge, rect) {
    switch (edge) {
    case "bottom": return rect.y + rect.height;
    case "left": return rect.x;
    case "right": return rect.x + rect.width;
    }
    return rect.y;
}

// The card's size across the line, which is how far behind it a closed card
// sits.
function across(edge, rect) {
    return vertical(edge) ? rect.width : rect.height;
}

// The card's rect ALONG the line, as a start and a length.
function alongStart(edge, rect) {
    return vertical(edge) ? rect.y : rect.x;
}

function alongLength(edge, rect) {
    return vertical(edge) ? rect.height : rect.width;
}

// Where the line lies, across it: the far edge of the surface this card
// hangs off (a tray item's menu off the tray's second bar), or, with none,
// the inner edge of the output's own band on that side. `insets` is
// Theme.edgeInset, the bar's thickness on the bar's edge and the frame
// ring's on the other three; 0 is a bare edge with no line at all, where the
// card comes out from behind the output itself.
function lineAt(edge, screenWidth, screenHeight, insets, targetRect) {
    if (targetRect) {
        switch (edge) {
        case "bottom": return targetRect.y;
        case "left": return targetRect.x + targetRect.width;
        case "right": return targetRect.x;
        }
        return targetRect.y + targetRect.height;
    }
    switch (edge) {
    case "bottom": return screenHeight - insets.bottom;
    case "left": return insets.left;
    case "right": return screenWidth - insets.right;
    }
    return insets.top;
}

// The room the card rests in between its own anchored edge and that line:
// one `barMargin` under the bar, one `screenPadding` off the ring.
function gap(edge, restRect, at) {
    return toLine(edge) * (at - nearEdge(edge, restRect));
}

// How far past its own rect the shape reaches back toward the line (M54 D6):
// that room, and the line's own row on top of it, so the fillets land ON the
// line and the two windows read as one silhouette.
function depth(edge, restRect, at, borderWidth) {
    return Math.max(0, gap(edge, restRect, at)) + borderWidth;
}

// Where that reach lands, which is the row the card is cut at.
function cut(edge, restRect, depthValue) {
    return nearEdge(edge, restRect) + toLine(edge) * depthValue;
}

// The band the card may paint in (M53 addendum, the drawer open): everything
// on the card's side of that cut, out to the far edge of the output. A card
// displaced behind the line by the emerge is cut there, so it comes out from
// under the bar rather than passing over it.
function clipBand(edge, at, screenWidth, screenHeight) {
    if (edge === "bottom")
        return { x: 0, y: 0, width: screenWidth, height: Math.max(0, at) };
    if (edge === "left")
        return { x: at, y: 0, width: Math.max(0, screenWidth - at), height: screenHeight };
    if (edge === "right")
        return { x: 0, y: 0, width: Math.max(0, at), height: screenHeight };
    return { x: 0, y: at, width: screenWidth, height: Math.max(0, screenHeight - at) };
}

// And what a card budding out of another surface's edge may paint on ALONG
// the line (M57 D3, Components/Joint.qml's `clip`): the band above, narrowed
// to the silhouette's own range, so a card clamped into its owner's span is
// revealed by the widening rather than drawn beside it. `range` null, which
// is every card that is not budding, leaves the band whole.
function clipAlong(band, edge, range) {
    if (!range)
        return band;
    var down = vertical(edge);
    var lo = down ? band.y : band.x;
    var hi = lo + (down ? band.height : band.width);
    var start = Math.max(lo, range.start);
    var extent = Math.max(0, Math.min(hi, range.start + range.length) - start);
    if (down)
        return { x: band.x, y: start, width: band.width, height: extent };
    return { x: start, y: band.y, width: extent, height: band.height };
}
