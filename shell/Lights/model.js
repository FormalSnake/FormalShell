.pragma library

// Pure model for LightsService. The service reads asusd's Aura object over
// busctl and writes through asusctl; this file parses the one and builds
// the argv for the other, so both ends are testable without a keyboard.
//
// `mode` is asusd's AuraModeNum, which is what LedMode and
// SupportedBasicModes carry (9 is unused upstream). `colours` is how many
// colour flags asusctl's subcommand takes, `speed` whether it takes one.
var EFFECTS = [
    { id: "static", label: "Static", mode: 0, colours: 1, speed: false },
    { id: "breathe", label: "Breathe", mode: 1, colours: 2, speed: true },
    { id: "rainbow-cycle", label: "Rainbow Cycle", mode: 2, colours: 0, speed: true },
    { id: "rainbow-wave", label: "Rainbow Wave", mode: 3, colours: 0, speed: true },
    { id: "stars", label: "Stars", mode: 4, colours: 2, speed: true },
    { id: "rain", label: "Rain", mode: 5, colours: 0, speed: true },
    { id: "highlight", label: "Highlight", mode: 6, colours: 1, speed: true },
    { id: "laser", label: "Laser", mode: 7, colours: 1, speed: true },
    { id: "ripple", label: "Ripple", mode: 8, colours: 1, speed: true },
    { id: "pulse", label: "Pulse", mode: 10, colours: 1, speed: false },
    { id: "comet", label: "Comet", mode: 11, colours: 1, speed: false },
    { id: "flash", label: "Flash", mode: 12, colours: 1, speed: false }
];

var SPEEDS = ["low", "med", "high"];

// asusd's Brightness property and `asusctl leds set`'s words, index for index.
var BRIGHTNESS = ["off", "low", "med", "high"];

var SOURCES = ["wallpaper", "custom"];

function effect(id) {
    for (var i = 0; i < EFFECTS.length; i++) {
        if (EFFECTS[i].id === id)
            return EFFECTS[i];
    }
    return null;
}

function effectForMode(mode) {
    for (var i = 0; i < EFFECTS.length; i++) {
        if (EFFECTS[i].mode === mode)
            return EFFECTS[i];
    }
    return null;
}

function usesColour(id) {
    var e = effect(id);
    return e !== null && e.colours > 0;
}

// "rrggbb" lowercase, or "" for anything else. Takes "#RRGGBB" too, which is
// what a person pastes.
function normalizeHex(text) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase();
    if (s.charAt(0) === "#")
        s = s.slice(1);
    return /^[0-9a-f]{6}$/.test(s) ? s : "";
}

function hexFromRgb(r, g, b) {
    function two(v) {
        var n = Math.max(0, Math.min(255, Math.round(v)));
        return (n < 16 ? "0" : "") + n.toString(16);
    }
    return two(r) + two(g) + two(b);
}

// busctl's text form: `u 0`, `au 3 0 1 2`, and for LedModeData
// `(uu(yyy)(yyy)ss) 0 0 67 133 190 0 0 0 "Med" "Right"` (mode, zone,
// colour1, colour2, speed, direction).
function parseProbe(text) {
    var out = { mode: -1, colour: "", speed: "", brightness: -1, modes: [] };
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var eq = lines[i].indexOf("=");
        if (eq < 0)
            continue;
        var key = lines[i].slice(0, eq);
        var value = lines[i].slice(eq + 1).trim();
        var m;
        if (key === "MODE" && (m = /^u (\d+)$/.exec(value)))
            out.mode = parseInt(m[1], 10);
        else if (key === "BRIGHT" && (m = /^u (\d+)$/.exec(value)))
            out.brightness = parseInt(m[1], 10);
        else if (key === "MODES" && (m = /^au \d+((?: \d+)*)$/.exec(value)))
            out.modes = m[1].trim() === "" ? [] : m[1].trim().split(" ").map(function (n) { return parseInt(n, 10); });
        else if (key === "DATA" && (m = /^\(\S+\) \d+ \d+ (\d+) (\d+) (\d+) \d+ \d+ \d+ "(\w+)"/.exec(value))) {
            out.colour = hexFromRgb(parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10));
            out.speed = m[4].toLowerCase();
        }
    }
    return out;
}

// The effects this chassis reports, in EFFECTS order. An empty report (an
// older asusd, a read that failed) offers the whole table rather than none.
function supported(modes) {
    if (!modes || modes.length === 0)
        return EFFECTS.slice();
    return EFFECTS.filter(function (e) { return modes.indexOf(e.mode) >= 0; });
}

// argv for one `asusctl aura effect` call, or null for an unknown effect.
// A two-colour effect gets the same colour twice, which asusd draws as a
// single-colour breathe or starfield.
function effectArgs(id, colour, speed) {
    var e = effect(id);
    if (e === null)
        return null;
    var args = ["asusctl", "aura", "effect", e.id];
    var hex = normalizeHex(colour) || "ffffff";
    if (e.colours >= 1)
        args.push("--colour", hex);
    if (e.colours >= 2)
        args.push("--colour2", hex);
    if (e.speed)
        args.push("--speed", SPEEDS.indexOf(speed) >= 0 ? speed : "med");
    if (e.id === "rainbow-wave")
        args.push("--direction", "right");
    return args;
}

function brightnessArgs(level) {
    return level >= 0 && level < BRIGHTNESS.length ? ["asusctl", "leds", "set", BRIGHTNESS[level]] : null;
}
