.pragma library

.import "flexoki.js" as Flexoki
.import "zenbones.js" as Zenbones

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

// A wallpaper whose path carries one of these names (any case, the
// substring test the DMS-era flexoki-pin reconciler used) is pinned to that
// palette instead of themed off its pixels. Each entry's module carries the
// three views a pinned matugen run rewrites its templates through
// (shadcn/materialRoles/base16) plus the source colour the run hands
// `matugen color hex` in place of the image, so the shell, theme.json and
// every app template read one table.
var PINNED = [
    { name: "flexoki", pattern: /flexoki/i, module: Flexoki },
    { name: "zenbones", pattern: /zenbones/i, module: Zenbones }
].map(function (entry) {
    return {
        name: entry.name,
        pattern: entry.pattern,
        shadcn: entry.module.shadcn,
        materialRoles: entry.module.materialRoles,
        base16: entry.module.base16,
        source: entry.module.SOURCE.replace("#", "").toUpperCase()
    };
});

function pinnedPalette(wallpaperPath) {
    if (typeof wallpaperPath !== "string")
        return null;
    for (var i = 0; i < PINNED.length; i++) {
        if (PINNED[i].pattern.test(wallpaperPath))
            return PINNED[i];
    }
    return null;
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
