.pragma library

// theme.preset (M49 D1): a table of chrome defaults, not a mode. Every knob
// a preset sets is a settings key the user can still write, and an explicit
// key always wins over the table. Resolution lives here so `Core/Theme.qml`
// stays the one file that reads a `theme.*` key: a surface reads `Theme.*`
// and never learns which preset is live.
//
// `shadcn` is the shipped design language (2026-08-25 redesign). `retro` is
// the one it replaced, square corners, one mono face, opaque surfaces with
// no compositor blur, and the dither pass over content imagery.

var NAMES = ["shadcn", "retro"];

var _TABLE = {
    shadcn: { radius: 10, icons: "lucide", fonts: "pair", surfaceOpacity: 0.85, blur: true, dither: false },
    retro: { radius: 0, icons: "nerd", fonts: "mono", surfaceOpacity: 1, blur: false, dither: true }
};

// Anything that is not one of NAMES resolves to shadcn, the same
// unknown-value habit icons.js keeps for an unknown icon set. Checked
// against NAMES rather than against _TABLE, so a settings value naming an
// inherited Object property ("constructor") reads as unknown too.
function _name(name) {
    return typeof name === "string" && NAMES.indexOf(name) !== -1 ? name : "shadcn";
}

// settings.json carries whatever the user typed, so a value that is not a
// real boolean is a malformed key rather than a falsy one: "true" and 1
// both take the preset's value instead of reading as on.
function _bool(value, fallback) {
    if (value === true)
        return true;
    if (value === false)
        return false;
    return fallback;
}

// A fresh object per call, so the table above stays the only copy of the
// numbers and a caller can hold what it gets back.
function defaults(name) {
    var d = _TABLE[_name(name)];
    return {
        radius: d.radius,
        icons: d.icons,
        fonts: d.fonts,
        surfaceOpacity: d.surfaceOpacity,
        blur: d.blur,
        dither: d.dither
    };
}

// `get` has Config.get's signature (path, fallback). Every read happens
// during this call, which is what lets a QML binding on the result track
// the settings object those reads touch.
//
// `theme.radius` and `theme.surfaceOpacity` pass through as written:
// Theme.qml range-checks both through Tokens.clamp, which is where that
// check already lived, and falls back to `defaults(preset)` for a value
// that is not a number at all.
function resolve(name, get) {
    var preset = _name(name);
    var d = _TABLE[preset];

    var fonts = get("theme.fonts", d.fonts);
    if (fonts !== "pair" && fonts !== "mono")
        fonts = d.fonts;

    var dither = _bool(get("theme.dither", d.dither), d.dither);

    return {
        preset: preset,
        radius: get("theme.radius", d.radius),
        icons: get("theme.icons", d.icons),
        fonts: fonts,
        surfaceOpacity: get("theme.surfaceOpacity", d.surfaceOpacity),
        blur: _bool(get("theme.blur", d.blur), d.blur),
        dither: dither,
        // The two full-screen image passes follow `theme.dither` unless they
        // say otherwise, so one key carries the texture everywhere and
        // either surface can still opt out on its own.
        wallpaperDither: _bool(get("wallpaper.dither", dither), dither),
        lockDither: _bool(get("lock.dither", dither), dither)
    };
}
