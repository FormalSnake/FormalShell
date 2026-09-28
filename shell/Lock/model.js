.pragma library

// The lock surface's two decisions that need no scene: which ink the words
// on the wallpaper take, and where the keyboard cursor over the now-playing
// transport goes (Surfaces/Lock/LockSurface.qml draws both).

// Ink by contrast against what is actually behind the words: the sampled
// wallpaper's mean luma (Theme/barpaint.js's `stats`, Rec. 601 on 0..255)
// under the surface's black scrim at `scrimAlpha`, or, with no wallpaper
// sampled, the flat colour the surface fills with instead (`fallbackLuma`,
// the same 0..255). "light" is white words, "dark" black ones, whichever
// has the larger WCAG contrast ratio against that backdrop; the two cross
// at a relative luminance of sqrt(0.0525) - 0.05, which is ~118 on 0..255.
// The theme's own foreground is never consulted: a light theme's near-black
// foreground over a dark wallpaper is exactly the case this exists for.
function backdropLuma(stats, scrimAlpha, fallbackLuma) {
    if (!stats || !stats.sampled)
        return fallbackLuma;
    return stats.mean * (1 - Math.max(0, Math.min(1, scrimAlpha)));
}

// sRGB's transfer function, 0..255 in, relative luminance 0..1 out.
function linear(value) {
    var c = Math.max(0, Math.min(255, value)) / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function contrast(a, b) {
    var hi = Math.max(a, b);
    var lo = Math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
}

function ink(stats, scrimAlpha, fallbackLuma) {
    var backdrop = linear(backdropLuma(stats, scrimAlpha, fallbackLuma));
    return contrast(1, backdrop) >= contrast(0, backdrop) ? "light" : "dark";
}

// A colour's Rec. 601 luma on 0..255, off Qt's 0..1 channels, for the
// fallback above.
function lumaOf(r, g, b) {
    return 255 * (0.299 * r + 0.587 * g + 0.114 * b);
}

// The transport cursor. The password field keeps keyboard focus for the
// whole time the surface is up and every key still reaches it first; this
// only decides which of those keys the transport takes instead. `index` is
// -1 while the cursor is off (the field's own state) and a button index
// while it is on; `count` is how many buttons there are, 0 while the block
// is hidden.
//
// Tab and Backtab walk the buttons and fall off either end back to the
// field. While a button holds the cursor, Left and Right step along the row
// (clamped, as ButtonGroup's own step() is), Enter presses it and Escape
// hands the cursor back. Anything else hands it back too and is NOT taken,
// so the first character of a password still lands in the field. Modifier
// presses on their own change nothing: Shift is half of Backtab.
//
// `key` is one of "tab", "backtab", "left", "right", "enter", "escape",
// "modifier" or "other". Returns the next index, whether the key was taken,
// and whether it pressed the button under the cursor.
function transportKey(index, count, key) {
    var out = { index: index, taken: false, press: false };
    if (count <= 0) {
        out.index = -1;
        return out;
    }
    if (index >= count)
        out.index = count - 1;
    if (key === "modifier")
        return out;
    if (key === "tab") {
        out.index = out.index + 1 >= count ? -1 : out.index + 1;
        out.taken = true;
        return out;
    }
    if (key === "backtab") {
        out.index = out.index < 0 ? count - 1 : out.index - 1;
        out.taken = true;
        return out;
    }
    if (out.index < 0)
        return out;
    switch (key) {
    case "left":
        out.index = Math.max(0, out.index - 1);
        out.taken = true;
        break;
    case "right":
        out.index = Math.min(count - 1, out.index + 1);
        out.taken = true;
        break;
    case "enter":
        out.press = true;
        out.taken = true;
        break;
    case "escape":
        out.index = -1;
        out.taken = true;
        break;
    default:
        out.index = -1;
        break;
    }
    return out;
}
