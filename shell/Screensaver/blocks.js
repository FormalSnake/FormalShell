.pragma library

// Cell-fraction geometry for the Unicode block elements (U+2580..U+259F),
// so the screensaver's Canvas can paint them as rectangles instead of
// glyphs.
//
// A terminal draws a block character by filling part of its own cell, which
// is why omarchy's screensaver (ttfx inside a real terminal) never shows a
// seam between two full blocks. A font is under no such obligation. Geist
// Mono's U+2588 inks y -340..960 against an hhea line box of -295..1005: the
// same height, sitting 45 units low, so it hangs out of the bottom of its own
// cell and leaves the top of it bare. Rasterized, it also comes up about a
// pixel short of the advance at the size this surface uses, which is a seam
// down every column of a solid banner. A face missing the range entirely
// hands the job to whatever fontconfig substitutes, with metrics of its own
// again. Painting the fraction each codepoint denotes takes the font out of
// the picture: the banner is solid under any installed monospace face,
// including one with no block coverage at all.
//
// Fractions, not pixels: x/y/w/h are 0..1 of one cell, y measured down from
// the cell's top edge. The caller owns the cell size and the pixel snapping
// two abutting cells need to share an edge.
//
// Scope is U+2580..U+259F and stops there, because those are the codepoints
// that have to TILE. Surveyed against ttfx 0.3.0 by running all 37 effects
// over the bundled banner and collecting every codepoint above ASCII: all 37
// emit the banner's own U+2580/2584/2588; beams adds the eighth blocks,
// errorcorrect and waves the lower eighths, burn the quadrants, print/smoke/
// sweep the shades, and every one of those lands in this range. Box drawing
// (U+2500..U+257F) shows up too, but as lines rather than fills: as the grid
// synthgrid rules, and as the scramble charset ttfx's own decrypt flickers
// through. A line is supposed to have background beside it, so there is no
// seam to close, and it keeps the font's glyph. So do the geometric shapes
// blackhole draws its collapsing core with (U+25C9, U+25CE, U+25CF, U+25E6)
// and the halfwidth katakana matrix rains.

var _EIGHTH = 1 / 8;
var _QUARTER = 1 / 4;

function _rect(x, y, w, h, alpha) {
    return { x: x, y: y, w: w, h: h, alpha: alpha === undefined ? 1 : alpha };
}

var FULL = [_rect(0, 0, 1, 1)];

// Quadrant bits, in the order the U+2596..U+259F names read.
var _UL = 1, _UR = 2, _LL = 4, _LR = 8;

// One rect per contiguous half wherever two quadrants share a full edge: two
// abutting rects would meet on a fractional pixel boundary and each cover
// half of it, which is the seam this whole file exists to avoid.
function _quadrants(mask) {
    var out = [];
    var top = (mask & _UL) && (mask & _UR);
    var bottom = (mask & _LL) && (mask & _LR);
    if (top) out.push(_rect(0, 0, 1, 0.5));
    if (bottom) out.push(_rect(0, 0.5, 1, 0.5));
    if (!top && (mask & _UL)) out.push(_rect(0, 0, 0.5, 0.5));
    if (!top && (mask & _UR)) out.push(_rect(0.5, 0, 0.5, 0.5));
    if (!bottom && (mask & _LL)) out.push(_rect(0, 0.5, 0.5, 0.5));
    if (!bottom && (mask & _LR)) out.push(_rect(0.5, 0.5, 0.5, 0.5));
    return out;
}

// The shades carry no geometry of their own: a terminal dithers them, and a
// dither over a cell this small is indistinguishable from the coverage it
// approximates. One full-cell rect at the coverage the name states, which
// the caller multiplies into whatever alpha it is already drawing at.
function _shade(coverage) {
    return [_rect(0, 0, 1, 1, coverage)];
}

var _TABLE = {};

_TABLE[0x2580] = [_rect(0, 0, 1, 0.5)];                       // upper half
for (var _n = 1; _n <= 7; _n++)                               // lower n eighths
    _TABLE[0x2580 + _n] = [_rect(0, 1 - _n * _EIGHTH, 1, _n * _EIGHTH)];
_TABLE[0x2588] = FULL;                                        // full block
for (var _m = 1; _m <= 7; _m++)                               // left (8-m) eighths
    _TABLE[0x2588 + _m] = [_rect(0, 0, (8 - _m) * _EIGHTH, 1)];
_TABLE[0x2590] = [_rect(0.5, 0, 0.5, 1)];                     // right half
_TABLE[0x2591] = _shade(_QUARTER);                            // light shade
_TABLE[0x2592] = _shade(0.5);                                 // medium shade
_TABLE[0x2593] = _shade(3 * _QUARTER);                        // dark shade
_TABLE[0x2594] = [_rect(0, 0, 1, _EIGHTH)];                   // upper one eighth
_TABLE[0x2595] = [_rect(1 - _EIGHTH, 0, _EIGHTH, 1)];         // right one eighth
_TABLE[0x2596] = _quadrants(_LL);
_TABLE[0x2597] = _quadrants(_LR);
_TABLE[0x2598] = _quadrants(_UL);
_TABLE[0x2599] = _quadrants(_UL | _LL | _LR);
_TABLE[0x259A] = _quadrants(_UL | _LR);
_TABLE[0x259B] = _quadrants(_UL | _UR | _LL);
_TABLE[0x259C] = _quadrants(_UL | _UR | _LR);
_TABLE[0x259D] = _quadrants(_UR);
_TABLE[0x259E] = _quadrants(_UR | _LL);
_TABLE[0x259F] = _quadrants(_UR | _LL | _LR);

// The rectangles covering `code`, or null when nothing here draws it and the
// caller should fall back to the font's own glyph. U+0020 is deliberately
// absent: an empty cell is not a rectangle of nothing, and callers skip it
// before asking.
function rectsFor(code) {
    var rects = _TABLE[code];
    return rects === undefined ? null : rects;
}

// Whether `rects` is the whole cell at full coverage, which is the one case a
// caller can widen across a horizontal run of the same codepoint and fill in
// a single call. The banner is mostly these.
function isFullCell(rects) {
    return rects !== null && rects.length === 1 && rects[0].x === 0 && rects[0].y === 0
        && rects[0].w === 1 && rects[0].h === 1 && rects[0].alpha === 1;
}

// Total ink coverage of one cell, 0..1. Not used to paint; it is how a test
// states what a codepoint means without restating the rectangle list, and it
// is what makes an overlapping or oversized table entry fail loudly.
function coverage(code) {
    var rects = rectsFor(code);
    if (rects === null)
        return 0;
    var total = 0;
    for (var i = 0; i < rects.length; i++)
        total += rects[i].w * rects[i].h * rects[i].alpha;
    return total;
}
