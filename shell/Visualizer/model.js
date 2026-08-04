.pragma library

// Pure mapping for the bar's ASCII audio visualizer (owner ask: "next to
// the now playing it would be nice to have an ASCII style audio
// visualizer"). VisualizerService feeds this cava's own raw ASCII output
// format one frame (one line) at a time: `BAR_COUNT` bar values 0..
// `MAX_LEVEL`, separated by `;` (cava's bar_delimiter default, decimal 59)
// — cava's own frame_delimiter default (decimal 10, `\n`) is what the
// Process's SplitParser already split on to hand us one line, so a frame
// never needs splitting on anything but `;` here. No Quickshell access, so
// the mapping/clamping/malformed-line paths are testable head-on.
// `BAR_COUNT`/`MAX_LEVEL` must match VisualizerService's generated
// cava.conf (`bars` / `ascii_max_range`) — the two are kept in the same
// place on purpose so they can't drift apart.
//
// Malformed input (wrong token count, non-numeric values, a blank or
// undefined line) parses to an all-zero frame rather than throwing — one
// bad line from cava must never crash the widget or freeze it on a stale
// render.

var GLYPHS = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];

// 6 bars at caption size, not 10 at body — the owner wants the cell
// DMS-compact ("less wide"), and a fixed-frequency spectrum reads fine
// at this resolution.
var BAR_COUNT = 6;
var MAX_LEVEL = 100;

function baselineText() {
    var s = "";
    for (var i = 0; i < BAR_COUNT; i++)
        s += GLYPHS[0];
    return s;
}

function parseFrame(line, barCount) {
    var count = barCount === undefined ? BAR_COUNT : barCount;
    var levels = new Array(count);
    for (var i = 0; i < count; i++)
        levels[i] = 0;
    if (typeof line !== "string" || line.length === 0)
        return levels;
    var parts = line.split(";");
    for (var i = 0; i < count && i < parts.length; i++) {
        var n = parseInt(parts[i], 10);
        levels[i] = (isNaN(n) || n < 0) ? 0 : n;
    }
    return levels;
}

// level 0..max -> glyph index, clamped to GLYPHS' own range regardless of
// how far out of band a malformed or autosens-overshooting value lands.
function levelToGlyph(level, maxLevel) {
    var max = maxLevel === undefined ? MAX_LEVEL : maxLevel;
    if (max <= 0)
        return GLYPHS[0];
    var idx = Math.floor((level / max) * GLYPHS.length);
    if (idx < 0)
        idx = 0;
    if (idx > GLYPHS.length - 1)
        idx = GLYPHS.length - 1;
    return GLYPHS[idx];
}

function frameToText(line, barCount, maxLevel) {
    var levels = parseFrame(line, barCount);
    var chars = new Array(levels.length);
    for (var i = 0; i < levels.length; i++)
        chars[i] = levelToGlyph(levels[i], maxLevel);
    return chars.join("");
}
