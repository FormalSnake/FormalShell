.pragma library

// Where the screen frame paints (Surfaces/Frame/Frame.qml). Pure, so the
// band and its corners are checkable without a compositor, the same split
// Bar/layout.js and Components/geometry.js use.
//
// The frame is the output less the bar strip (`outer`), with a rounded
// rectangle cut out of it (`inner`): `thickness` in from every edge the
// bar is not on, and flush against the bar on its edge, so the two corners
// beside the bar curve into the strip and the strip reads as the frame's
// thick side. What the frame paints is the ring between the two, never the
// strip itself, which the bar already paints at the same alpha. `radius`
// is capped so the cut-out is never asked for corners it cannot hold.
function frameGeometry(width, height, barInset, thickness, radius) {
    var t = thickness > 0 ? thickness : 0;
    var outer = {
        x: barInset.left,
        y: barInset.top,
        width: Math.max(0, width - barInset.left - barInset.right),
        height: Math.max(0, height - barInset.top - barInset.bottom)
    };
    var left = barInset.left > 0 ? 0 : t;
    var top = barInset.top > 0 ? 0 : t;
    var right = barInset.right > 0 ? 0 : t;
    var bottom = barInset.bottom > 0 ? 0 : t;
    var inner = {
        x: outer.x + left,
        y: outer.y + top,
        width: Math.max(0, outer.width - left - right),
        height: Math.max(0, outer.height - top - bottom)
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
