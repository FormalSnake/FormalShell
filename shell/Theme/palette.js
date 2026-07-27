.pragma library

// theme.json's six required color keys, plus the hex format matugen
// renders them in, and the static Flexoki values Theme.qml falls back to
// when theme.json is absent or fails validation.

var COLOR_KEYS = ["background", "backgroundAlt", "foreground", "foregroundDim", "accent", "urgent"];
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
        accent: "#4385BE", urgent: "#D14D41"
    };
}
