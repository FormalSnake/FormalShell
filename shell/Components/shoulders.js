.pragma library

// Shoulders.qml's outline, as pure functions (the same split
// Components/geometry.js and Frame/geometry.js already use).
//
// The card meets the bar on one edge and carries a concave quarter fillet
// outside each of that edge's two corners, so the card and the bar's line
// read as one silhouette rather than as a card parked against a line
// (M54 D6). The fillets sit OUTSIDE the card, `radius` along the bar on
// either side, which is why the item is `2 * radius` longer than the card on
// that axis and hangs at `cardX - radius`.
//
// The outline is built once in a canonical space and mapped onto the item:
// `u` runs along the bar (0 at the card's near end, `length` at its far
// one), `v` inward from the bar's line. `bottom` and `left` mirror that
// space onto the item, which reverses the sweep of every arc.

function vertical(edge) {
    return edge === "left" || edge === "right";
}

// Whether mapping the canonical space onto the item mirrors it, which is the
// one thing an arc's sweep flag depends on.
function mirrored(edge) {
    return edge === "bottom" || edge === "left";
}

// The eight points of the outline, in the item's own coordinates, for a path
// drawn `inset` in from the card's rect: 0 for the fill, half a stroke for
// the border, so a 1px line lands on one pixel row the way a Rectangle's own
// border does. A fillet is concave, its material lies outside it, so it
// offsets the other way (`r + inset`) and both paths still end at the same
// two outer points: the bar's gap is one number whichever of them measures
// it.
//
// The traversal starts on the bar's line at the near fillet's outer end and
// runs away from it, so the anchored edge is the one segment left open:
//   p0  the near fillet's outer end, on the bar's line
//   p1  where that fillet meets the card's near side
//   p2  p3  the near free corner
//   p4  p5  the far free corner
//   p6  where the far fillet leaves the card's far side
//   p7  the far fillet's outer end, on the bar's line
function outline(edge, width, height, radius, inset) {
    var r = radius > 0 ? radius : 0;
    var i = inset > 0 ? inset : 0;
    var along = (vertical(edge) ? height : width);
    var depth = (vertical(edge) ? width : height);
    var length = Math.max(0, along - r * 2);
    // The three free corners are capped by the card they round. The fillets
    // are not: they are the join's own radius, and the gap the bar opens is
    // measured off it, so capping them would move the line's ends away from
    // where the arcs actually land.
    var rc = Math.max(0, Math.min(r, Math.min(length, depth) / 2) - i);
    var rf = r > 0 ? r + i : 0;
    var far = depth - i;
    var canonical = [
        [i - rf, i],
        [i, i + rf],
        [i, far - rc],
        [i + rc, far],
        [length - i - rc, far],
        [length - i, far - rc],
        [length - i, i + rf],
        [length - i + rf, i]
    ];
    var p = [];
    for (var n = 0; n < canonical.length; n++)
        p.push(_map(edge, width, height, r, canonical[n][0], canonical[n][1]));
    return {
        p: p,
        overhang: r,
        convexRadius: rc,
        filletRadius: rf,
        mirrored: mirrored(edge)
    };
}

// Canonical (u, v) onto the item. `over` is the near fillet's room along the
// bar axis, which is where the card's own near end starts.
function _map(edge, width, height, over, u, v) {
    if (edge === "bottom")
        return { x: over + u, y: height - v };
    if (edge === "left")
        return { x: v, y: over + u };
    if (edge === "right")
        return { x: width - v, y: over + u };
    return { x: over + u, y: v };
}
