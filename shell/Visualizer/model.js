.pragma library

// Pure mapping for the bar's dithered audio visualizer (owner ask: "next to
// the now playing it would be nice to have an ASCII style audio
// visualizer", M20 Task 4: "for consistency, the audio visualizer can also
// have the dithered ASCII effect like progress bars"). VisualizerService
// feeds this cava's own raw ASCII output format one frame (one line) at a
// time: `BAR_COUNT` bar values 0..`MAX_LEVEL`, separated by `;` (cava's
// bar_delimiter default, decimal 59), cava's own frame_delimiter default
// (decimal 10, `\n`) is what the Process's SplitParser already split on to
// hand us one line, so a frame never needs splitting on anything but `;`
// here. No Quickshell access, so the mapping/clamping/malformed-line paths
// are testable head-on.
// `BAR_COUNT`/`MAX_LEVEL` must match VisualizerService's generated
// cava.conf (`bars` / `ascii_max_range`), the two are kept in the same
// place on purpose so they can't drift apart.
//
// Malformed input (wrong token count, non-numeric values, a blank or
// undefined line) parses to an all-zero frame rather than throwing, one
// bad line from cava must never crash the widget or freeze it on a stale
// render.

// cava's own bar count (M55: raised from 6 to 24 for the media panel's
// spectrum band, which draws every column at the panel's own width). The
// bar cell still reads as six tracks: Visualizer.qml downsamples
// VisualizerService.levels to CELL_BAR_COUNT below rather than drawing all
// 24 at the cell's own DMS-compact size.
var BAR_COUNT = 24;
var MAX_LEVEL = 100;

// The bar cell's own track count: 6 bars at caption size, not 10 at body,
// the owner wants the cell DMS-compact ("less wide"), and a
// fixed-frequency spectrum reads fine at this resolution.
var CELL_BAR_COUNT = 6;

// Below this level a bar reads as silence and snaps flat. cava's own
// `ignore` knob would do the same job but has been deprecated since 0.8.0
// (verified against its 0.10.7 example config), and doing it here keeps the
// threshold visible next to the curve it interacts with.
var NOISE_FLOOR = 2;

// Square root, not linear. A linear level->height map spends most of its
// range on peaks a real track almost never hits, so a bar sits pinned near
// zero and barely moves; sqrt lifts the mid-levels where music actually
// lives. This is the same perceptual curve DMS applies to its own cava
// values (`Math.sqrt(x * 0.01)` in `Modules/DankBar/Widgets/AudioVisualization.qml`)
// and is the larger half of why theirs reads livelier, the other half is
// VisualizerService's cava tuning (fixed sensitivity, monstercat spread).
function _response(fraction) {
    return Math.sqrt(fraction);
}

// All-zero levels, the bar's own dithered-track baseline (DESIGN.md §4
// item 8): empty fills, pure dither, no live spectrum.
function baselineLevels() {
    var levels = new Array(BAR_COUNT);
    for (var i = 0; i < BAR_COUNT; i++)
        levels[i] = 0;
    return levels;
}

// Folds a `BAR_COUNT`-long frame down to `count` columns for the bar cell,
// each the peak (not the average) of its own contiguous group: a peak keeps
// a transient visible even when it lands in only one of the four raw bars a
// cell column now stands for, where an average would smear it out. Groups
// split as evenly as possible when `levels.length` doesn't divide by
// `count`, the remainder spread one-wide over the first groups so no group
// but the last ever comes up short. A group with nothing in it (levels
// shorter than count) reads as its own zero rather than an out-of-bounds
// read, which is what makes an empty or short frame downsample to zeros.
function downsample(levels, count) {
    var input = levels || [];
    var result = new Array(count);
    var base = Math.floor(input.length / count);
    var remainder = input.length % count;
    var idx = 0;
    for (var g = 0; g < count; g++) {
        var size = base + (g < remainder ? 1 : 0);
        var peak = 0;
        for (var j = 0; j < size; j++) {
            if (input[idx + j] > peak)
                peak = input[idx + j];
        }
        idx += size;
        result[g] = peak;
    }
    return result;
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

// level 0..max -> 0..1 fill fraction through the response curve, clamped
// to 0..1 regardless of how far out of band a malformed or overshooting
// value lands. A bar's own track height times this fraction is the solid
// fill's height; the rest of the column stays dither.
function levelToFraction(level, maxLevel) {
    var max = maxLevel === undefined ? MAX_LEVEL : maxLevel;
    if (max <= 0 || level < NOISE_FLOOR)
        return 0;
    var fraction = _response(level / max);
    if (fraction < 0)
        fraction = 0;
    if (fraction > 1)
        fraction = 1;
    return fraction;
}

function frameToLevels(line, barCount, maxLevel) {
    var levels = parseFrame(line, barCount);
    var fractions = new Array(levels.length);
    for (var i = 0; i < levels.length; i++)
        fractions[i] = levelToFraction(levels[i], maxLevel);
    return fractions;
}

// Level-color bands (M20 Task 4b, owner: "the audio visualizer can
// potentially be colored bar per bar, keeping the ASCII style ofc"): each
// column's own post-response-curve fraction (the same 0..1 value
// VisualizerService.levels already carries) sorts into one of three ink
// bands so a bar's color reads as its energy, not a per-index rainbow
// (DESIGN.md §1.4's loud-color law rules out decoration).
//
// M20 Task 5b replaced this with per-bar colors sampled from the playing
// track's cover; the owner rejected that on the live shell 2026-08-10
// ("the album cover's colors are ugly just keep it like it was before"),
// so the bands are the shipped default again and the cover palette is
// gone.
//
// Chosen against the sqrt curve above, not the raw cava range: a quarter
// of MAX_LEVEL already reads half-scale (0.5 fraction, see
// test_level_to_fraction_applies_the_square_root_response_curve), so a 0.4
// cut sits around the bottom sixth of the raw range (~16/100): silence
// and near-silence stay dim, anything with real presence reads as content.
// 0.85 sits high enough (~72/100 raw) that only the tuned config's own
// measured loud-passage peaks (▄▅▅▆▇█, VisualizerService.qml's own
// pink-noise reading) cross it, so accent stays a peak signal, spent, not
// worn.
var LEVEL_DIM_BELOW = 0.4;
var LEVEL_ACCENT_FROM = 0.85;

// "dim" | "content" | "accent": pure classification, no color values.
// QML resolves each band to a Theme role/inversion pair on its own.
function levelColorBand(level) {
    if (level >= LEVEL_ACCENT_FROM)
        return "accent";
    if (level >= LEVEL_DIM_BELOW)
        return "content";
    return "dim";
}
