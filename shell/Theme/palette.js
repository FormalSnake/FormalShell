.pragma library

// theme.json's six required color keys, plus the hex format matugen
// renders them in, and the static Flexoki values Theme.qml falls back to
// when theme.json is absent or fails validation.

var COLOR_KEYS = ["background", "backgroundAlt", "foreground", "foregroundDim", "accent", "urgent", "rule", "onAccent"];
var HEX_RE = /^#[0-9a-fA-F]{6}$/;

function validate(themeObj) {
    var missing = [];
    COLOR_KEYS.forEach(function (key) {
        var value = themeObj ? themeObj[key] : undefined;
        if (typeof value !== "string" || !HEX_RE.test(value)) missing.push(key);
    });
    return { ok: missing.length === 0, missing: missing };
}

function fallback() {
    return {
        mode: "dark",
        background: "#100F0F", backgroundAlt: "#1C1B1A",
        foreground: "#CECDC3", foregroundDim: "#878580",
        accent: "#4385BE", urgent: "#D14D41",
        rule: "#403E3C", onAccent: "#FFFCF0"
    };
}

// Per-key backward-tolerant merge: a theme.json written before a key existed
// (or mid-write with one bad value) falls back to Flexoki for that key alone
// — never the whole object, so a live matugen run stays themed everywhere
// except the one stale/missing field.
function mergeWithFallback(themeObj) {
    var fb = fallback();
    var merged = { mode: (themeObj && typeof themeObj.mode === "string") ? themeObj.mode : fb.mode };
    COLOR_KEYS.forEach(function (key) {
        var value = themeObj ? themeObj[key] : undefined;
        merged[key] = (typeof value === "string" && HEX_RE.test(value)) ? value : fb[key];
    });
    return merged;
}
