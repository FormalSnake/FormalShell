.pragma library

// wingpanel's adaptive panel, as pure functions (M60 T3, the 2026-09-17
// spec's Part 2): the statistics of the wallpaper band under the bar, and
// the paint they decide. Transcribed from elementary's own GPL sources,
// `wingpanel-interface/BackgroundManager.vala` for the decision and gala's
// `Background.get_color_information` for the three numbers it reads.
// Nothing is ported; the recipe is read and the band is sampled here.
//
// The numbers below are the decision's own constants and live with it
// rather than in a theme table: a table describes how a band is painted,
// this decides which of its paints the wallpaper asks for.
//
// BarPaint.qml samples the wallpaper's own pixels, never the screen
// (LockSurface.qml's header: no `ScreencopyView`, ever). A window under the
// band is not sampled, which is wingpanel's own compromise and the reason
// it goes solid the moment one covers the output.

// Rec. 601 luma, the weighting gala reads a wallpaper's brightness with,
// on 0..255.
var LUMA_R = 0.299;
var LUMA_G = 0.587;
var LUMA_B = 0.114;

// A band is bright above this mean, busy above either of the next two, and
// the sigma rule catches a band whose mean is dark but whose spread puts a
// twentieth of it in the light: 1.645 is the 95th percentile of a normal
// distribution, which is elementary's own reading of "bright enough parts
// to matter".
var LUMA_THRESHOLD = 180;
var STD_THRESHOLD = 45;
var ACUTANCE_THRESHOLD = 8;
var SIGMA = 1.645;

// How wide the whole wallpaper is sampled, the band's own rows taken out of
// that. A few hundred pixels is what the three statistics need: the mean
// and the spread are scale-free, and the acutance keeps its edges as long
// as the downscale is nearest-neighbour (BarPaint.qml turns smoothing off
// for exactly that reason).
var SAMPLE_WIDTH = 240;

// The three numbers, off one RGBA run (a Canvas `getImageData().data`) of
// `width` by `height` samples. `acutance` is the mean absolute luminance
// difference between horizontally adjacent samples, so a flat field reads 0
// and a checker reads the contrast between its squares.
function stats(data, width, height) {
    var count = width * height;
    if (!data || count <= 0)
        return { mean: 0, std: 0, acutance: 0, sampled: false };

    var sum = 0;
    var square = 0;
    var edge = 0;
    var edges = 0;
    for (var y = 0; y < height; y++) {
        var prev = -1;
        for (var x = 0; x < width; x++) {
            var i = (y * width + x) * 4;
            var luma = LUMA_R * data[i] + LUMA_G * data[i + 1] + LUMA_B * data[i + 2];
            sum += luma;
            square += luma * luma;
            if (prev >= 0) {
                edge += Math.abs(luma - prev);
                edges++;
            }
            prev = luma;
        }
    }
    var mean = sum / count;
    // Clamped at 0: the variance of a flat field is a difference of two
    // large sums and lands a hair below zero in floating point.
    var variance = Math.max(0, square / count - mean * mean);
    return {
        mean: mean,
        std: Math.sqrt(variance),
        acutance: edges > 0 ? edge / edges : 0,
        sampled: true
    };
}

// Whether the band is too busy to read ink off directly, which is what
// makes wingpanel draw a translucent panel at all.
function busy(s) {
    if (!s || !s.sampled)
        return false;
    return s.std > STD_THRESHOLD
        || s.acutance > ACUTANCE_THRESHOLD
        || (s.mean < LUMA_THRESHOLD && s.mean + SIGMA * s.std > LUMA_THRESHOLD);
}

// The paint, one of the five the table describes. A window covering the
// output wins over everything the wallpaper says, since none of it is
// visible then. With no wallpaper set there is nothing to sample and
// nothing to invent: the honest answer is the bare band with light ink.
function decide(s, mode, fullscreen) {
    if (fullscreen)
        return "maximized";
    if (!s || !s.sampled)
        return "light";
    if (busy(s))
        return mode === "light" ? "translucentLight" : "translucentDark";
    return s.mean > LUMA_THRESHOLD ? "dark" : "light";
}

// The band's rect inside a sample of the whole wallpaper: the bar's own
// edge and thickness against the output's size, scaled and clamped so a
// band thinner than one sample row still has a row to read.
function bandRect(edge, thickness, screenWidth, screenHeight, sampleWidth, sampleHeight) {
    var across = Math.max(1, Math.round(thickness / Math.max(1, screenHeight) * sampleHeight));
    var down = Math.max(1, Math.round(thickness / Math.max(1, screenWidth) * sampleWidth));
    switch (edge) {
    case "bottom":
        return { x: 0, y: Math.max(0, sampleHeight - across), width: sampleWidth, height: across };
    case "left":
        return { x: 0, y: 0, width: down, height: sampleHeight };
    case "right":
        return { x: Math.max(0, sampleWidth - down), y: 0, width: down, height: sampleHeight };
    default:
        return { x: 0, y: 0, width: sampleWidth, height: across };
    }
}
