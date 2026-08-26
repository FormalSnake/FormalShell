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
