.pragma library

// Where the screen frame paints (Surfaces/Frame/Frame.qml). Pure, so the
// band and its corners are checkable without a compositor, the same split
// Bar/layout.js and Components/geometry.js use.
//
// The frame is the whole output (`outer`) with a rounded rectangle cut out
// of it (`inner`): `insets` in from every edge, which is the bar's own
// thickness on its edge and the band's `thickness` on the other three
// (Theme.edgeInset). The ring between the two is one fill, strip included:
// the bar draws only its cells over it, so the strip and the band are one
// blurred surface with no seam where one would hand over to the other.
// `radius` is capped so the cut-out is never asked for corners it cannot
// hold.
function frameGeometry(width, height, insets, radius) {
    var outer = { x: 0, y: 0, width: Math.max(0, width), height: Math.max(0, height) };
    var inner = {
        x: insets.left,
        y: insets.top,
        width: Math.max(0, width - insets.left - insets.right),
        height: Math.max(0, height - insets.top - insets.bottom)
    };
    var r = Math.max(0, Math.min(radius > 0 ? radius : 0, Math.min(inner.width, inner.height) / 2));
    return { outer: outer, inner: inner, radius: r };
}

// The cut-out shrunk by half a stroke, so a line drawn along it lies inside
// the band rather than straddling its edge.
function strokeRect(inner, radius, strokeWidth) {
    var half = strokeWidth / 2;
    return {
        x: inner.x + half,
        y: inner.y + half,
        width: Math.max(0, inner.width - strokeWidth),
        height: Math.max(0, inner.height - strokeWidth),
        radius: Math.max(0, radius - half)
    };
}

// The ring's hairline as one open walk round the cut-out, clockwise, with a
// gap on the bar's own side between `gapStart` and `gapEnd` (window
// coordinates along that side, the span a joined card's shoulders draw
// into: Surfaces/Bar/Bar.qml's `_gapStart`/`_gapEnd`). Ten points: the walk
// starts at one end of the gap, takes the four sides and the four corner
// arcs, and ends at the gap's other end, so the segments alternate line,
// arc, line, arc from p0 to p9 whichever side the bar is on. The gap is
// held to the straight run of that side, and an empty one lands both ends
// on the corner where the walk begins, which is a whole ring.
function lineWalk(inner, radius, edge, gapStart, gapEnd) {
    var x = inner.x;
    var y = inner.y;
    var w = inner.width;
    var h = inner.height;
    var r = radius;
    var vertical = edge === "left" || edge === "right";
    var along = vertical ? h : w;
    var origin = vertical ? y : x;
    var lo = Math.max(r, Math.min(along - r, gapStart - origin));
    var hi = Math.max(lo, Math.min(along - r, gapEnd - origin));
    if (edge === "left")
        return [
            { x: x, y: y + lo }, { x: x, y: y + r }, { x: x + r, y: y },
            { x: x + w - r, y: y }, { x: x + w, y: y + r },
            { x: x + w, y: y + h - r }, { x: x + w - r, y: y + h },
            { x: x + r, y: y + h }, { x: x, y: y + h - r }, { x: x, y: y + hi }
        ];
    if (edge === "right")
        return [
            { x: x + w, y: y + hi }, { x: x + w, y: y + h - r }, { x: x + w - r, y: y + h },
            { x: x + r, y: y + h }, { x: x, y: y + h - r },
            { x: x, y: y + r }, { x: x + r, y: y },
            { x: x + w - r, y: y }, { x: x + w, y: y + r }, { x: x + w, y: y + lo }
        ];
    if (edge === "bottom")
        return [
            { x: x + lo, y: y + h }, { x: x + r, y: y + h }, { x: x, y: y + h - r },
            { x: x, y: y + r }, { x: x + r, y: y },
            { x: x + w - r, y: y }, { x: x + w, y: y + r },
            { x: x + w, y: y + h - r }, { x: x + w - r, y: y + h }, { x: x + hi, y: y + h }
        ];
    return [
        { x: x + hi, y: y }, { x: x + w - r, y: y }, { x: x + w, y: y + r },
        { x: x + w, y: y + h - r }, { x: x + w - r, y: y + h },
        { x: x + r, y: y + h }, { x: x, y: y + h - r },
        { x: x, y: y + r }, { x: x + r, y: y }, { x: x + lo, y: y }
    ];
}
