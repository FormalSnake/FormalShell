.pragma library

// theme.json's twelve required color keys (DESIGN.md §1.5, expanded
// 2026-08-07 from the original eight), plus the hex format matugen
// renders them in, and the static Flexoki values Theme.qml falls back to
// when theme.json is absent or fails validation.
//
// These roles are also the color tokens DESIGN.md §1's state/border token
// system (Theme.qml's `stateStyle`/`borderSpec`, `tokens.js`) resolves
// against — a state names a role (`foreground`, `accent`, `urgent`,
// `background`) or a raw hex, never a new color key of its own.

var COLOR_KEYS = ["background", "backgroundAlt", "foreground", "foregroundDim", "foregroundFaint",
    "rule", "accent", "onAccent", "urgent", "onUrgent", "warning", "onWarning"];
var HEX_RE = /^#[0-9a-fA-F]{6}$/;

function validate(themeObj) {
    var missing = [];
    COLOR_KEYS.forEach(function (key) {
        var value = themeObj ? themeObj[key] : undefined;
        if (typeof value !== "string" || !HEX_RE.test(value)) missing.push(key);
    });
    return { ok: missing.length === 0, missing: missing };
}

// One static Flexoki variant per mode (hex values from kepano/flexoki:
// dark = base 950/800/500/200 on black with the 400 accents, light =
// base 50/200/600 on paper with the 600 accents; faint = base 700 dark /
// base 400 light, warning = orange 400 dark / orange 600 light). No
// argument means the dark variant — the seeded first-boot theme.json and
// Theme.qml's absent-file default both depend on that. Dark `onAccent` and
// `onUrgent`/`onWarning` are ink (#100F0F), not paper — measured contrast
// beats paper-on-accent (DESIGN.md's 2026-08-07 revision); light keeps
// paper on all three fills.
function fallback(mode) {
    if (mode === "light") {
        return {
            mode: "light",
            background: "#FFFCF0", backgroundAlt: "#F2F0E5",
            foreground: "#100F0F", foregroundDim: "#6F6E69", foregroundFaint: "#9F9D96",
            rule: "#CECDC3", accent: "#205EA6", onAccent: "#FFFCF0",
            urgent: "#AF3029", onUrgent: "#FFFCF0", warning: "#BC5215", onWarning: "#FFFCF0"
        };
    }
    return {
        mode: "dark",
        background: "#100F0F", backgroundAlt: "#1C1B1A",
        foreground: "#CECDC3", foregroundDim: "#878580", foregroundFaint: "#575653",
        rule: "#403E3C", accent: "#4385BE", onAccent: "#100F0F",
        urgent: "#D14D41", onUrgent: "#100F0F", warning: "#DA702C", onWarning: "#100F0F"
    };
}

// Per-key backward-tolerant merge: a theme.json written before a key existed
// (or mid-write with one bad value) falls back to Flexoki for that key alone
// — never the whole object, so a live matugen run stays themed everywhere
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
