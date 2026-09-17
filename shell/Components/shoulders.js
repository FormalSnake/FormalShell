.pragma library

// Shoulders.qml's outline, as pure functions (the same split
// Components/geometry.js and Frame/geometry.js already use).
//
// The card meets a line on one edge (the bar's hairline, the frame ring's)
// and carries a concave quarter fillet outside each of that edge's two
// corners, so the card and the line read as one silhouette rather than as
// a card parked against a line (M54 D6). The fillets sit OUTSIDE the card,
// `radius` along the line on either side, which is why the item is
// `2 * radius` longer than the card on that axis and hangs at
// `cardX - radius`.
//
// The join lets go (2026-09-14, the metamorphosis): `near` moves the card's
// anchored edge in from the item's line edge, and `corner` is that edge's
// two corners as one signed radius, concave (positive, the fillets) through
// sharp (0) to convex (negative, a card's own rounded corner). Shoulders.qml
// runs both off one attach factor, so a card pulls off the line with its
// fillets shrinking to nothing and its corners rounding out, and at
// `corner: -radius` with any `near` this is a plain card with four rounded
// corners, the same rect Card.qml draws.
//
// A side of the card resting closer than `radius` to where its line ends is
// WALLED (M57 D2): there is no room for a fillet, so while the card is
// attached its silhouette simply runs out to that wall. `walls` carries how
// far past the card's own rect each end runs to reach it (negative for a
// side with room), the attach factor that run rides, and the radius the two
// lines meet in (`walls.radius`: a frame ring's rounded cut-out, 0 for the
// output's own square edge). A walled side's two corners swap roles: the one
// on the line follows that corner while the fill flows into the wall, since a
// square one paints over the band a ring's corner curves in by, and relaxes
// into the card's own convex rounding as the card lets go; the one on the far
// edge takes the signed radius, so the fillet is the near one turned a
// quarter, centred one radius out from the far edge and one radius in from
// the wall. That fillet is what the item grows by on its far side, and only
// while a side is walled (`farOverhang`).
//
// The outline is built once in a canonical space and mapped onto the item:
// `u` runs along the line (0 at the card's near end, `length` at its far
// one), `v` inward from the line. `bottom` and `left` mirror that space
// onto the item, which reverses the sweep of every arc.

function vertical(edge) {
    return edge === "left" || edge === "right";
}

// Whether mapping the canonical space onto the item mirrors it, which is the
// one thing an arc's sweep flag depends on.
function mirrored(edge) {
    return edge === "bottom" || edge === "left";
}

// The concave fillet's radius for a shape `depth` deep past the line: the
// join's own radius until the shape is shallower than that.
function filletRadius(radius, depth) {
    return Math.max(0, Math.min(radius, depth));
}

// How far the item runs past the card along the line at either end: enough
// for a fillet, or for the run out to a wall when that is further. One
// number for both ends, so the consumer still hangs the item at
// `cardX - overhang` with `cardWidth + overhang * 2`; the room the unwalled
// end does not use is simply never painted.
function overhang(radius, wallStart, wallEnd) {
    var r = radius > 0 ? radius : 0;
    return Math.max(r, wallStart > 0 ? wallStart : 0, wallEnd > 0 ? wallEnd : 0);
}

// And how far it runs past the card's FAR edge: one radius while a side is
// walled, for the concave fillet that corner carries against the wall, and
// nothing otherwise, which is every consumer that never walls.
function farOverhang(radius, wallStart, wallEnd) {
    var r = radius > 0 ? radius : 0;
    return (wallStart >= 0 || wallEnd >= 0) ? r : 0;
}

// The eight points of the outline, in the item's own coordinates, for a path
// drawn `inset` in from the card's rect: 0 for the fill, half a stroke for
// the border, so a 1px line lands on one pixel row the way a Rectangle's own
// border does. A concave corner's material lies outside it, so it offsets
// the other way (`r + inset`) and both paths still end at the same two
// outer points: the line's gap is one number whichever of them measures
// it. A convex corner offsets inward like the far corners do.
//
// The traversal starts on the near edge at the near corner's outer end and
// runs away from it, so the near edge is the one segment left open, the
// closing run from p7 back to p0 along `v = near`:
//   p0  the near corner's start on the near edge (on the line, and a fillet
//       outside the card, while the card is attached)
//   p1  where that corner meets the card's near side
//   p2  p3  the near free corner
//   p4  p5  the far free corner
//   p6  where the far near-corner leaves the card's far side
//   p7  that corner's end on the near edge
// On a walled side the same eight points describe the run out to the wall:
// the side's own edge is the wall rather than the card's rect, the corner on
// the line collapses to a square one, and the corner on the far edge becomes
// the concave fillet against the wall. `arcs` is the four corner arcs in
// path order with the radius and sweep each of them ended up with, so the
// consumer never has to know which side was walled.
//
// `farGap`, `[start, end]` along the item's own bar axis or null, is a gap
// in the far edge for a card hanging off THIS one (a tray item's menu off
// the tray's second bar): `g[0]` and `g[1]` are where the far edge's stroke
// stops and resumes, both on p4 when there is no gap.
//
// `lip` holds the path off the line's own row, on top of whatever `inset`
// and `near` already give: the fill takes `borderWidth` while the card is
// attached, so the line's row carries the line's window alone rather than
// two translucent fills, and the fill's fillet then shares its centre with
// the stroke's (same centre, radius `r` against `r + borderWidth / 2`). The
// stroke passes 0 and keeps its half-stroke inset. A wall that carries a
// line of its own takes the same lip along its own edge, and the fillet
// against it stays concentric for the same reason. The radii are capped off
// the un-lipped depth so the two paths stay concentric on a shape shallower
// than the radius, which also keeps the gap the line opens one number.
function outline(edge, width, height, radius, inset, near, corner, farGap, lip, walls) {
    var r = radius > 0 ? radius : 0;
    var i = inset > 0 ? inset : 0;
    var n = near > 0 ? near : 0;
    var ws = (walls && walls.start >= 0) ? walls.start : -1;
    var we = (walls && walls.end >= 0) ? walls.end : -1;
    var at = (walls && walls.attach > 0) ? Math.min(1, walls.attach) : 0;
    var over = overhang(r, ws, we);
    var lift = farOverhang(r, ws, we);
    var along = (vertical(edge) ? height : width);
    var depth = (vertical(edge) ? width : height) - lift;
    var length = Math.max(0, along - over * 2);
    var body = Math.max(0, depth - n);
    var l = Math.max(0, Math.min(lip > 0 ? lip : 0, body));
    // The three free corners are capped by the card they round. The fillets
    // are capped by the depth alone: a card coming out from under the line
    // is shallower than the join's radius for its first frames, and a
    // fillet deeper than the card would run past the card's own far edge.
    // The gap the line opens is measured off the same number (Joint.qml
    // publishes it as the join's `reach`), so the line's ends stay where
    // the arcs actually land.
    var rc = Math.max(0, Math.min(r, Math.min(length, body) / 2) - i);
    var c = corner === undefined ? r : corner;
    var concave = c >= 0;
    var rn = concave
        ? (c > 0 ? filletRadius(c, body) + i : 0)
        : Math.max(0, Math.min(-c, Math.min(length, body) / 2) - i);
    var signed = concave ? rn : -rn;
    // The walled side's corner on the line. A wall that carries a line of its
    // own ends in a corner of its own radius (a frame ring's cut-out), and the
    // fill has to follow it: a square corner there covers the wedge of band
    // the ring's corner curves in by, which on two translucent surfaces reads
    // as a lighter triangle in the corner. It relaxes into the card's own
    // convex rounding as the card comes off both lines. A wall that is the
    // output's own edge has no corner to follow: square for as long as the
    // near corners are concave, then rounding out convex with them.
    var wr = (walls && walls.radius > 0) ? walls.radius : 0;
    var rq = wr > 0
        ? Math.max(0, Math.min(wr * at + r * (1 - at), Math.min(length, body) / 2) - i)
        : (concave ? 0 : rn);
    var far = depth - i;
    var top = n + i + l;
    // Where a walled side's own edge is drawn: out on the wall while
    // attached, back on the card's rect once it has let go, and held off the
    // wall's own line row by the same inset and lip the near edge takes.
    var uStart = ws >= 0 ? i - ws * at + l : i;
    var uEnd = we >= 0 ? length - i + we * at - l : length - i;
    var runStart = ws >= 0 ? uStart + rn : i + rc;
    var runEnd = we >= 0 ? uEnd - rn : length - i - rc;
    var ga = runEnd;
    var gb = runEnd;
    if (farGap) {
        ga = Math.max(runStart, Math.min(runEnd, farGap[0] - over));
        gb = Math.max(ga, Math.min(runEnd, farGap[1] - over));
    }
    var canonical = (ws >= 0
        ? [[uStart + rq, top], [uStart, top + rq], [uStart, far + signed], [runStart, far]]
        : [[i - signed, top], [i, top + rn], [i, far - rc], [runStart, far]]
    ).concat(we >= 0
        ? [[runEnd, far], [uEnd, far + signed], [uEnd, top + rq], [uEnd - rq, top]]
        : [[runEnd, far], [length - i, far - rc], [length - i, top + rn], [length - i + signed, top]]);
    var p = [];
    for (var k = 0; k < canonical.length; k++)
        p.push(_map(edge, width, height, over, canonical[k][0], canonical[k][1]));
    return {
        p: p,
        g: [_map(edge, width, height, over, ga, far), _map(edge, width, height, over, gb, far)],
        arcs: [
            { r: ws >= 0 ? rq : rn, concave: ws >= 0 ? false : concave },
            { r: ws >= 0 ? rn : rc, concave: ws >= 0 ? concave : false },
            { r: we >= 0 ? rn : rc, concave: we >= 0 ? concave : false },
            { r: we >= 0 ? rq : rn, concave: we >= 0 ? false : concave }
        ],
        walled: [ws >= 0, we >= 0],
        overhang: over,
        farOverhang: lift,
        mirrored: mirrored(edge)
    };
}

// Canonical (u, v) onto the item. `over` is the item's room along the line
// outside the card's own rect, which is where the card's near end starts.
function _map(edge, width, height, over, u, v) {
    if (edge === "bottom")
        return { x: over + u, y: height - v };
    if (edge === "left")
        return { x: v, y: over + u };
    if (edge === "right")
        return { x: width - v, y: over + u };
    return { x: over + u, y: v };
}
