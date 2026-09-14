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

// The ring's hairline as twelve strokes: each side of the cut-out in two
// runs, split at the gap a joined card's shoulders draw into on that side
// (`gaps[edge]` is `[start, end]` in window coordinates along the side, the
// span Surfaces/Bar/Bar.qml's `_gapStart`/`_gapEnd` computes, absent for a
// side with nothing on it), and the four corner arcs, clockwise. Sides are
// cut only on their straight run; a gap outside it or empty gives a second
// run of nothing and a first that is the whole side. Strokes are separate
// so any side can open on any frame, which one walk cannot do once two
// cards are up on two sides at once.
function ringLine(inner, radius, gaps) {
    var x = inner.x;
    var y = inner.y;
    var w = inner.width;
    var h = inner.height;
    var r = radius;
    function runs(edge, origin, extent, a, b) {
        var g = gaps && gaps[edge] ? gaps[edge] : null;
        var lo = g ? Math.max(r, Math.min(extent - r, g[0] - origin)) : extent - r;
        var hi = g ? Math.max(lo, Math.min(extent - r, g[1] - origin)) : extent - r;
        return [[r, lo], [hi, extent - r]];
    }
    var top = runs("top", x, w);
    var bottom = runs("bottom", x, w);
    var left = runs("left", y, h);
    var right = runs("right", y, h);
    return {
        sides: {
            top: top.map(function (s) { return { x1: x + s[0], y1: y, x2: x + s[1], y2: y }; }),
            right: right.map(function (s) { return { x1: x + w, y1: y + s[0], x2: x + w, y2: y + s[1] }; }),
            bottom: bottom.map(function (s) { return { x1: x + s[0], y1: y + h, x2: x + s[1], y2: y + h }; }),
            left: left.map(function (s) { return { x1: x, y1: y + s[0], x2: x, y2: y + s[1] }; })
        },
        corners: [
            { x1: x + w - r, y1: y, x2: x + w, y2: y + r },
            { x1: x + w, y1: y + h - r, x2: x + w - r, y2: y + h },
            { x1: x + r, y1: y + h, x2: x, y2: y + h - r },
            { x1: x, y1: y + r, x2: x + r, y2: y }
        ]
    };
}
