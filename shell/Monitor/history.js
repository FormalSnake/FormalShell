.pragma library

// Rolling samples behind the monitor's sparklines. A sample that could not be
// taken (the first tick of a delta, a card with no counter) is left out
// rather than stored as a zero, so a line only ever draws measured points.

// Two minutes at the default 2s poll.
var CAPACITY = 60;

function push(series, value, capacity) {
    var out = (series || []).slice();
    if (typeof value !== "number" || !isFinite(value))
        return out;
    out.push(value);
    var cap = capacity || CAPACITY;
    return out.length > cap ? out.slice(out.length - cap) : out;
}

// The scale a byte-rate series is drawn against: its own peak, but never
// below `floor`, so an idle link's noise does not fill the box.
function ceiling(series, floor) {
    var top = floor;
    for (var i = 0; i < (series || []).length; i++) {
        if (series[i] > top)
            top = series[i];
    }
    return top;
}

// Polyline points for a series in a width x height box, y up from the
// bottom. A series shorter than `capacity` is spread across the whole box
// rather than crowded against the right edge, so a monitor that has just
// opened still draws a line you can read; once the series is full the
// newest sample sits on the right edge and the rest step left.
function points(series, width, height, top, capacity) {
    var cap = capacity || CAPACITY;
    var values = series || [];
    var out = [];
    if (!(top > 0) || cap < 2)
        return out;
    var slots = Math.min(values.length, cap);
    for (var i = 0; i < values.length; i++) {
        var fraction = Math.max(0, Math.min(1, values[i] / top));
        out.push({ x: slots > 1 ? i / (slots - 1) * width : width, y: height - fraction * height });
    }
    return out;
}
