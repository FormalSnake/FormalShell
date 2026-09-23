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
// 1000 rather than 100: VisualizerService's gain stage divides by a running
// peak that can sit near the bottom of the range on a quiet track, and at
// 100 steps a band there only has a handful of values to move through.
var MAX_LEVEL = 1000;

// The bar cell's own track count: 6 bars at caption size, not 10 at body,
// the owner wants the cell DMS-compact ("less wide"), and a
// fixed-frequency spectrum reads fine at this resolution.
var CELL_BAR_COUNT = 6;

// Below this level a bar reads as silence and snaps flat. cava's own
// `ignore` knob would do the same job but has been deprecated since 0.8.0
// (verified against its 0.10.7 example config), and doing it here keeps the
// threshold visible next to the curve it interacts with. 5/1000 at cava's
// sensitivity 200 is the same acoustic level as 2/100 at 800%, where it was
// measured.
var NOISE_FLOOR = 5;

// The gain stage (M73). cava runs at a fixed, low sensitivity so a loud
// master never clips at its ceiling, and the height comes from here
// instead: every band is divided by `ref`, a peak follower on the frame's
// loudest raw band, so a loud track and a quiet one both draw with the same
// headroom. cava's own autosens is not the answer, it drives every passage
// to full scale, which is the complaint this replaces.
//
// Attack 0.12s, so a louder passage stops overdrawing within a few frames
// rather than pegging for a second. Release is a constant 20dB (10x) fall
// every 4s, in the log domain rather than an exponential toward the peak: a
// quiet track after a loud one is back to full height within those 4s
// whatever the size of the drop, while a half-level dip inside a song
// still reads as a dip for ~1.2s.
//
// AGC_FLOOR caps the gain at AGC_TARGET / AGC_FLOOR. 0.04 sits under the
// quiet pink-noise passage's own peak at sensitivity 200 (~0.09, a quarter
// of its ~0.36 reading at 800%), so quiet material still normalizes, and
// eight times over NOISE_FLOOR, so a band hovering just over the floor draws
// under a fifth of the column instead of being lifted into motion.
var AGC_ATTACK_SECONDS = 0.12;
var AGC_RELEASE_SECONDS = 4;
var AGC_FLOOR = 0.04;

// Where the running peak draws, before the knee: a steady loud passage's
// loudest band lands at 0.757 after it, the upper third with a quarter of
// the column left for transients.
var AGC_TARGET = 0.8;

// Above AGC_KNEE the height bends toward 1 and never reaches it (unit
// slope at the knee, so no visible kink): 36% over the running peak draws
// 0.85, 2x draws 0.93, 3x draws 0.976. Only a transient gets near the top.
var AGC_KNEE = 0.6;

// A power under 1 on the peak-relative level lifts the mid-levels, kept
// milder than sqrt so neighbouring bands stay apart once the gain has
// lifted them: a band at a quarter of the peak draws 0.30 against the
// peak's 0.757, where sqrt would put it at half the peak's height.
var RESPONSE_POWER = 0.7;

// Returns the next `ref`. A `ref` of 0 or less is the reset state
// VisualizerService starts from and returns to when cava stops: it snaps to
// the first frame's own peak, so every play does not open on a frame
// divided by the floor. A non-finite or non-positive `dtSeconds` moves
// nothing past that snap.
function agcStep(ref, framePeak, dtSeconds) {
    var peak = (typeof framePeak === "number" && isFinite(framePeak) && framePeak > 0) ? framePeak : 0;
    if (!(ref > 0))
        return Math.max(peak, AGC_FLOOR);
    var next = ref;
    if (typeof dtSeconds === "number" && isFinite(dtSeconds) && dtSeconds > 0) {
        if (peak > ref)
            next = ref + (peak - ref) * (1 - Math.exp(-dtSeconds / AGC_ATTACK_SECONDS));
        else
            next = Math.max(peak, ref * Math.pow(10, -dtSeconds / AGC_RELEASE_SECONDS));
    }
    return Math.max(next, AGC_FLOOR);
}

function _knee(z) {
    if (z <= AGC_KNEE)
        return z;
    var span = 1 - AGC_KNEE;
    return AGC_KNEE + span * (1 - Math.exp(-(z - AGC_KNEE) / span));
}

// Raw 0..1 fraction -> drawn 0..1 height against the running peak `ref`.
function normalize(fraction, ref) {
    if (!(fraction > 0))
        return 0;
    var r = ref > AGC_FLOOR ? ref : AGC_FLOOR;
    return _knee(Math.pow(fraction / r, RESPONSE_POWER) * AGC_TARGET);
}

function framePeak(fractions) {
    var peak = 0;
    var input = fractions || [];
    for (var i = 0; i < input.length; i++) {
        if (input[i] > peak)
            peak = input[i];
    }
    return peak;
}

function levelFrame(fractions, ref) {
    var input = fractions || [];
    var result = new Array(input.length);
    for (var i = 0; i < input.length; i++)
        result[i] = normalize(input[i], ref);
    return result;
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

// cava's own frame arrives on its own clock (VisualizerService's framerate)
// while the screen repaints on the compositor's, and the two are never the
// same rate. Rather than snapping the drawn levels to whatever frame cava
// last sent, VisualizerService carries them toward it a little every screen
// frame, so the motion runs at the display's own rate regardless of how
// cava's frames land (M55 A3). `1 - exp(-dt / tau)` is the standard
// exponential approach to a moving target: independent of dt, so a slow
// screen frame and a fast one converge at the same real-time rate rather
// than overshooting or lagging. Rising and falling take different time
// constants: quick on the way up so a transient still reads as a hit, slower
// on the way down so a bar doesn't blink off between two loud frames the way
// a linear decay would.
var RISE_SECONDS = 0.03;
var FALL_SECONDS = 0.09;

// Returns a NEW array, `target.length` long: `shown` is read, never
// mutated, since VisualizerService's own `levels` binding is what's being
// carried forward here. A `shown` shorter than `target` reads its missing
// entries as 0 (a bar that just appeared starts from silence); a `shown`
// longer than `target` has its extra entries dropped, reconciling the two
// lengths. A non-finite or non-positive `dtSeconds` (a stalled or repeated
// frame) moves nothing: the reconciled `shown` values pass through
// unchanged rather than jumping to `target` or extrapolating from a
// meaningless delta.
function smoothLevels(shown, target, dtSeconds) {
    var from = shown || [];
    var to = target || [];
    var result = new Array(to.length);
    var canMove = typeof dtSeconds === "number" && isFinite(dtSeconds) && dtSeconds > 0;
    for (var i = 0; i < to.length; i++) {
        var start = from[i] || 0;
        if (!canMove) {
            result[i] = start;
            continue;
        }
        var tau = to[i] >= start ? RISE_SECONDS : FALL_SECONDS;
        var factor = 1 - Math.exp(-dtSeconds / tau);
        result[i] = start + (to[i] - start) * factor;
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

// level 0..max -> raw 0..1 fraction, linear, clamped to 0..1 regardless of
// how far out of band a malformed or overshooting value lands. The height a
// bar draws is `normalize` of this, never this directly.
function levelToFraction(level, maxLevel) {
    var max = maxLevel === undefined ? MAX_LEVEL : maxLevel;
    if (max <= 0 || level < NOISE_FLOOR)
        return 0;
    var fraction = level / max;
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
// Chosen against `normalize` above, so both cuts are relative to the
// running peak rather than to cava's range: 0.4 is a band ~37% of the peak
// (-8.6dB), anything quieter stays dim. A steady loud passage's loudest band
// draws 0.757, so 0.85 is only crossed by a band 36% over the running peak:
// accent stays a transient signal, spent, not worn.
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
