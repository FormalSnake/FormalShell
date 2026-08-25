.pragma library

// The palette engine behind DitherImage.qml's "retro" pass (DESIGN.md §2
// item 12), pure JS so the color math is reachable from a test without a
// Canvas, the same split every other algorithmic surface here uses
// (Screensaver/effect.js, Menu/search.js).
//
// What this replaced and why (owner, live shell, 2026-08-12: "the dithering
// looks cool for the wallpaper, but its too intense and it adds dots to
// monotone wallpapers ... I want the dithering engine to make images look
// like 90s wallpapers/ascii pixelart"): the pass used to posterize each RGB
// channel independently onto `levels` evenly-spaced steps (3, so 0/128/255,
// 27 colors) with a Bayer bias tipping a channel across a step boundary.
// Two things follow from a fixed, evenly-spaced grid of steps, and both are
// exactly what the owner reported:
//
// - A flat region whose color sits anywhere near a step boundary dithers
//   forever, at up to a 50/50 checker, because the boundary is a property of
//   the grid and not of the image. A monotone wallpaper is one such region
//   the size of the screen, so it speckled end to end.
// - The two colors being mixed are a full step apart, 128 per channel at
//   3 levels, so every one of those dots is maximum contrast. That is the
//   "too intense".
//
// A period-correct image instead carries a SMALL palette chosen FOR that
// image (an Amiga/VGA-era conversion, and the owner's reference is exactly
// this: one 5-color indigo ramp for a whole night scene), and dithers only
// between palette entries that are already neighbors. So:
//
// - `palette()` derives up to `maxColors` colors from the image itself by
//   median cut. A solid or near-solid source collapses to a single entry,
//   which is the whole fix for the dots: its own color IS in the palette, so
//   there is nothing to mix it with.
// - `quantize()` picks each cell's nearest palette entry, and only tips it
//   to the SECOND nearest by the 4x4 Bayer threshold, weighted by how far
//   between the two the cell actually sits. Cells that land on a palette
//   entry never dither at all; cells exactly halfway land on a 50/50
//   checker, the same as before, but between two colors the image itself
//   put next to each other, so a dense region reads as shading rather than
//   as noise.
//
// Hue survives for the same reason it did before, more strongly: entries are
// real averages of the image's own colors, so nothing is forced onto a gray
// axis and nothing can drift to a hue the source never contained. This is
// display-side only, nothing here is ever written to disk, and matugen still
// reads the untouched wallpaper FILE (ThemeEngine.qml), so a dithered
// rendering cannot seed the color scheme.

// 4x4 ordered Bayer matrix, values 0..15 mapped to a per-cell threshold.
// Shared with DitherImage's duotone pass, one matrix, one convention.
var BAYER = [
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5
];

// Histogram resolution: 5 bits per channel, 32768 buckets. Coarse enough
// that a photograph collapses to a few thousand populated buckets (which is
// what keeps the median cut below cheap), fine enough that two colors a
// viewer can tell apart never merge. Bucket AVERAGES, not bucket centers,
// become the palette, so this quantization never shifts a color: a solid
// #8e44ad image yields #8e44ad exactly.
var _HIST_BITS = 5;
var _HIST_SIZE = 1 << (_HIST_BITS * 3);

// Population, and the per-channel sums that give a box its average color.
// Parallel arrays rather than an array of objects: one allocation per
// channel for the whole histogram instead of one object per populated
// bucket, on a path that runs over every cell of a full-screen wallpaper.
function _buckets(cells, cellCount) {
    var map = new Array(_HIST_SIZE);
    var n = [], sr = [], sg = [], sb = [];
    for (var i = 0; i < cellCount; i++) {
        var o = i * 3;
        var r = cells[o], g = cells[o + 1], b = cells[o + 2];
        var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
        var bucket = map[key];
        if (bucket === undefined) {
            bucket = n.length;
            map[key] = bucket;
            n.push(0);
            sr.push(0);
            sg.push(0);
            sb.push(0);
        }
        n[bucket]++;
        sr[bucket] += r;
        sg[bucket] += g;
        sb[bucket] += b;
    }
    return { n: n, sr: sr, sg: sg, sb: sb };
}

// A median-cut box: the buckets it holds, its population, its own average
// color (population-weighted, so a box's entry sits where its pixels
// actually are rather than at its geometric center), and the channel it is
// longest along, the axis a split would cut.
function _box(buckets, h) {
    var pop = 0, tr = 0, tg = 0, tb = 0;
    var minR = 256, maxR = -1, minG = 256, maxG = -1, minB = 256, maxB = -1;
    for (var i = 0; i < buckets.length; i++) {
        var k = buckets[i];
        var c = h.n[k];
        pop += c;
        tr += h.sr[k];
        tg += h.sg[k];
        tb += h.sb[k];
        var r = h.sr[k] / c, g = h.sg[k] / c, b = h.sb[k] / c;
        if (r < minR) minR = r;
        if (r > maxR) maxR = r;
        if (g < minG) minG = g;
        if (g > maxG) maxG = g;
        if (b < minB) minB = b;
        if (b > maxB) maxB = b;
    }
    var axis = 0, range = maxR - minR;
    if (maxG - minG > range) { axis = 1; range = maxG - minG; }
    if (maxB - minB > range) { axis = 2; range = maxB - minB; }
    return {
        buckets: buckets,
        population: pop,
        axis: axis,
        range: range,
        r: Math.round(tr / pop),
        g: Math.round(tg / pop),
        b: Math.round(tb / pop)
    };
}

// Cuts a box in two at the median of its population along its longest axis
// (hence the algorithm's name): both halves hold about the same number of
// pixels, so palette entries land where the image spends its pixels instead
// of spreading evenly over a color volume most of the image never visits.
function _split(box, h) {
    var sums = box.axis === 0 ? h.sr : (box.axis === 1 ? h.sg : h.sb);
    var sorted = box.buckets.slice().sort(function (a, b) {
        return sums[a] / h.n[a] - sums[b] / h.n[b];
    });
    var half = box.population / 2;
    var acc = 0, cut = 0;
    for (var i = 0; i < sorted.length - 1; i++) {
        acc += h.n[sorted[i]];
        cut = i + 1;
        if (acc >= half)
            break;
    }
    if (cut <= 0 || cut >= sorted.length)
        return null;
    return [_box(sorted.slice(0, cut), h), _box(sorted.slice(cut), h)];
}

// `cells`: flat r,g,b triples (0..255), `cellCount` triples long. Returns a
// flat r,g,b palette, AT MOST `maxColors` entries and often fewer, an image
// with less color than that in it gets a shorter palette rather than
// duplicate entries a dither would then mix between for no reason. Capped at
// 256 entries because quantize() answers in a Uint8Array of indices; nothing
// near that is a palette anyone would call reduced anyway.
function palette(cells, cellCount, maxColors) {
    var want = Math.min(256, Math.max(1, maxColors));
    var h = _buckets(cells, cellCount);
    if (h.n.length === 0)
        return [];

    var all = [];
    for (var k = 0; k < h.n.length; k++)
        all.push(k);
    var boxes = [_box(all, h)];

    while (boxes.length < want) {
        // Split the box with the most pixels TIMES the widest color range:
        // population alone spends the whole palette on a large flat sky,
        // range alone spends it on a handful of stray bright pixels.
        var pick = -1, best = 0;
        for (var i = 0; i < boxes.length; i++) {
            var box = boxes[i];
            if (box.buckets.length < 2 || box.range <= 0)
                continue;
            var score = box.range * box.population;
            if (score > best) {
                best = score;
                pick = i;
            }
        }
        if (pick < 0)
            break;
        var halves = _split(boxes[pick], h);
        if (!halves)
            break;
        boxes.splice(pick, 1, halves[0], halves[1]);
    }

    var out = [];
    for (var b = 0; b < boxes.length; b++)
        out.push(boxes[b].r, boxes[b].g, boxes[b].b);
    return out;
}

// Maps every cell onto a palette index, ordered-dithering between the two
// nearest entries. `gridWidth` is what makes the Bayer threshold a function
// of the cell's position in the grid rather than of its position in the flat
// array.
//
// `t` is the cell projected onto the line from its nearest entry to its
// second nearest, so it is 0 when the cell IS the nearest color and 0.5 when
// it sits exactly between the two (it can never exceed 0.5, past that the
// other entry would have been the nearer one). Choosing the second entry
// when `t` exceeds the Bayer threshold makes the proportion of stepped-up
// cells equal `t`, so a flat area of a color the palette holds shows no
// pattern at all and everything in between averages back to the color the
// source actually had.
function quantize(cells, cellCount, gridWidth, pal) {
    var count = pal.length / 3;
    // Uint8Array, not a plain Array: a full-screen pass indexes hundreds of
    // thousands of cells, and this is the one allocation per paint that
    // scales with the screen, a boxed-double array of the same length is
    // eight times the garbage on a path the animated album art re-runs
    // several times a second.
    var out = new Uint8Array(cellCount);
    if (count === 0)
        return out;
    for (var i = 0; i < cellCount; i++) {
        var o = i * 3;
        var r = cells[o], g = cells[o + 1], b = cells[o + 2];
        var near = -1, nearD = Infinity, second = -1, secondD = Infinity;
        for (var p = 0; p < count; p++) {
            var po = p * 3;
            var dr = r - pal[po], dg = g - pal[po + 1], db = b - pal[po + 2];
            var d = dr * dr + dg * dg + db * db;
            if (d < nearD) {
                secondD = nearD;
                second = near;
                nearD = d;
                near = p;
            } else if (d < secondD) {
                secondD = d;
                second = p;
            }
        }
        if (second < 0 || nearD === 0) {
            out[i] = near < 0 ? 0 : near;
            continue;
        }
        var ao = near * 3, bo = second * 3;
        var ex = pal[bo] - pal[ao], ey = pal[bo + 1] - pal[ao + 1], ez = pal[bo + 2] - pal[ao + 2];
        var len = ex * ex + ey * ey + ez * ez;
        var t = len > 0
            ? ((r - pal[ao]) * ex + (g - pal[ao + 1]) * ey + (b - pal[ao + 2]) * ez) / len
            : 0;
        if (t <= 0) {
            out[i] = near;
            continue;
        }
        if (t > 0.5)
            t = 0.5;
        var x = i % gridWidth, y = (i / gridWidth) | 0;
        out[i] = t > (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16 ? second : near;
    }
    return out;
}

function _hex2(n) {
    var h = n.toString(16);
    return h.length < 2 ? "0" + h : h;
}

function hex(r, g, b) {
    return "#" + _hex2(r) + _hex2(g) + _hex2(b);
}

// One `fillStyle` string per palette entry, built once per paint and indexed
// per run. Formatting a fresh hex string per cell instead was measured at
// 491ms against 198ms for a lookup (mac VM rig, 1920x1080); a full-screen
// source is the first caller where that difference is a visible stall.
function hexPalette(pal) {
    var out = [];
    for (var i = 0; i < pal.length; i += 3)
        out.push(hex(pal[i], pal[i + 1], pal[i + 2]));
    return out;
}
