.pragma library

// theme.json's shadcn color roles (spec "Visual system > Color",
// 2026-08-25 redesign), plus the hex format matugen renders them in, and
// the static zinc values Theme.qml falls back to when theme.json is absent
// or fails validation.

var COLOR_KEYS = ["background", "foreground", "card", "cardForeground",
    "popover", "popoverForeground", "primary", "primaryForeground",
    "secondary", "secondaryForeground", "muted", "mutedForeground",
    "accent", "accentForeground", "destructive", "destructiveForeground",
    "warning", "warningForeground", "border", "input", "ring",
    "chart1", "chart2", "chart3", "chart4", "chart5"];
var HEX_RE = /^#[0-9a-fA-F]{6}$/;

function validate(themeObj) {
    var missing = [];
    COLOR_KEYS.forEach(function (key) {
        var value = themeObj ? themeObj[key] : undefined;
        if (typeof value !== "string" || !HEX_RE.test(value)) missing.push(key);
    });
    return { ok: missing.length === 0, missing: missing };
}

// One static zinc variant per mode (shadcn's own zinc palette, spec's
// "Color" table verbatim). No argument means the dark variant: the
// seeded first-boot theme.json and Theme.qml's absent-file default both
// depend on that. `accent` is the neutral hover fill (not the wallpaper
// colour, which lives in `primary`); chart1..5 reuse primary, secondary,
// warning and two zinc steps since the static fallback has no matugen
// container roles to draw the chart ramp from.
function fallback(mode) {
    if (mode === "light") {
        return {
            mode: "light",
            background: "#ffffff", foreground: "#09090b",
            card: "#ffffff", cardForeground: "#09090b",
            popover: "#ffffff", popoverForeground: "#09090b",
            primary: "#18181b", primaryForeground: "#fafafa",
            secondary: "#f4f4f5", secondaryForeground: "#18181b",
            muted: "#f4f4f5", mutedForeground: "#71717a",
            accent: "#f4f4f5", accentForeground: "#18181b",
            destructive: "#e7000b", destructiveForeground: "#ffffff",
            warning: "#d97706", warningForeground: "#ffffff",
            border: "#e4e4e7", input: "#e4e4e7", ring: "#a1a1aa",
            chart1: "#18181b", chart2: "#f4f4f5", chart3: "#d97706",
            chart4: "#d4d4d8", chart5: "#52525b"
        };
    }
    return {
        mode: "dark",
        background: "#09090b", foreground: "#fafafa",
        card: "#18181b", cardForeground: "#fafafa",
        popover: "#18181b", popoverForeground: "#fafafa",
        primary: "#e4e4e7", primaryForeground: "#18181b",
        secondary: "#27272a", secondaryForeground: "#fafafa",
        muted: "#27272a", mutedForeground: "#a1a1aa",
        accent: "#27272a", accentForeground: "#fafafa",
        destructive: "#ff6467", destructiveForeground: "#fafafa",
        warning: "#fbbf24", warningForeground: "#18181b",
        border: "#27272a", input: "#3f3f46", ring: "#71717a",
        chart1: "#e4e4e7", chart2: "#27272a", chart3: "#fbbf24",
        chart4: "#3f3f46", chart5: "#71717a"
    };
}

// A wallpaper whose path carries "flexoki" (any case, the substring test
// the DMS-era flexoki-pin reconciler used) is pinned to Flexoki
// (stephango.com/flexoki) instead of themed off its pixels: the shell skips
// matugen for it and writes this palette the way it writes zinc with no
// wallpaper. Base tones fill the surfaces (black/b950/b900 dark, paper/b50/
// b100 light), blue is `primary` and `ring` (the colour Flexoki's own site
// links in), the 400 stops sit on dark and the 600 stops on light, and
// chart1..5 walk the accents since this palette has real ones to draw from.
function pinsFlexoki(wallpaperPath) {
    return typeof wallpaperPath === "string" && /flexoki/i.test(wallpaperPath);
}

// What a pinned run hands `matugen color hex` in place of the image, so the
// user's own templates land in Flexoki's hue: blue-400, the dark primary
// below. The light primary is the same hue toned down, so one source serves
// both modes and the hue family never flips on a mode toggle.
var FLEXOKI_SOURCE = "4385BE";

function flexoki(mode) {
    if (mode === "light") {
        return {
            mode: "light",
            background: "#fffcf0", foreground: "#100f0f",
            card: "#f2f0e5", cardForeground: "#100f0f",
            popover: "#e6e4d9", popoverForeground: "#100f0f",
            primary: "#205ea6", primaryForeground: "#fffcf0",
            secondary: "#e6e4d9", secondaryForeground: "#100f0f",
            muted: "#e6e4d9", mutedForeground: "#6f6e69",
            accent: "#dad8ce", accentForeground: "#100f0f",
            destructive: "#af3029", destructiveForeground: "#fffcf0",
            warning: "#bc5215", warningForeground: "#fffcf0",
            border: "#dad8ce", input: "#dad8ce", ring: "#205ea6",
            chart1: "#205ea6", chart2: "#24837b", chart3: "#bc5215",
            chart4: "#66800b", chart5: "#5e409d"
        };
    }
    return {
        mode: "dark",
        background: "#100f0f", foreground: "#cecdc3",
        card: "#1c1b1a", cardForeground: "#cecdc3",
        popover: "#282726", popoverForeground: "#cecdc3",
        primary: "#4385be", primaryForeground: "#100f0f",
        secondary: "#282726", secondaryForeground: "#cecdc3",
        muted: "#282726", mutedForeground: "#878580",
        accent: "#343331", accentForeground: "#cecdc3",
        destructive: "#d14d41", destructiveForeground: "#100f0f",
        warning: "#da702c", warningForeground: "#100f0f",
        border: "#403e3c", input: "#403e3c", ring: "#4385be",
        chart1: "#4385be", chart2: "#3aa99f", chart3: "#da702c",
        chart4: "#879a39", chart5: "#8b7ec8"
    };
}

// Per-key backward-tolerant merge: a theme.json written before a key existed
// (or mid-write with one bad value) falls back to zinc for that key alone,
// never the whole object, so a live matugen run stays themed everywhere
// except the one stale/missing field. The fill matches the theme's own mode
// so a partial light theme.json never flashes dark tokens into a light UI.
function mergeWithFallback(themeObj) {
    var fb = fallback(themeObj && themeObj.mode === "light" ? "light" : "dark");
    var merged = { mode: (themeObj && typeof themeObj.mode === "string") ? themeObj.mode : fb.mode };
    COLOR_KEYS.forEach(function (key) {
        var value = themeObj ? themeObj[key] : undefined;
        merged[key] = (typeof value === "string" && HEX_RE.test(value)) ? value : fb[key];
    });
    return merged;
}
