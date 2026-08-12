.pragma library

// Pure resolver for `hotCorners` (settings.json). Takes the raw object in,
// returns { enabled, size, delayMs, corners, warnings } out — no Quickshell
// or Config access, so it's testable head-on, same shape as Bar/layout.js.
// Bad input is never fatal: an unrecognised action name or a non-numeric
// size is dropped with one warning string rather than thrown, since a typo
// in settings.json must never take the whole shell down with it.

var CORNERS = ["topLeft", "topRight", "bottomLeft", "bottomRight"];

var ACTIONS = ["none", "screensaver", "lock"];

// Both top corners default to "none": Bar.qml anchors top/left/right, so a
// hot corner up there would take its trigger square out of the bar's own
// input region — the leftmost pixels of the workspace cell, the rightmost
// of the indicators one.
var DEFAULT_CORNERS = { topLeft: "none", topRight: "none", bottomLeft: "screensaver", bottomRight: "lock" };

// The trigger square, in pixels. Small on purpose and still not hard to
// hit: the compositor clamps the cursor at the screen edge, so throwing the
// pointer at a corner parks it on the last pixel regardless of how fast it
// was moving. The size only decides how much of the screen stops being
// clickable, never how hard the corner is to reach.
var DEFAULT_SIZE = 4;
var MAX_SIZE = 64;

// Dwell before the action fires, so a pointer merely passing through a
// corner on its way somewhere else never locks the session.
var DEFAULT_DELAY_MS = 400;
var MAX_DELAY_MS = 10000;

function _clampedNumber(value, fallback, min, max, key, warnings) {
    if (value === undefined || value === null)
        return fallback;
    var n = Number(value);
    if (!isFinite(n)) {
        warnings.push("hotCorners." + key + ": expected a number, got " + JSON.stringify(value));
        return fallback;
    }
    return Math.max(min, Math.min(max, Math.round(n)));
}

function resolve(hotCorners) {
    var warnings = [];
    var raw = (hotCorners && typeof hotCorners === "object") ? hotCorners : {};
    var corners = {};
    for (var i = 0; i < CORNERS.length; i++) {
        var name = CORNERS[i];
        var action = raw[name];
        if (action === undefined || action === null) {
            corners[name] = DEFAULT_CORNERS[name];
            continue;
        }
        if (typeof action !== "string" || ACTIONS.indexOf(action) < 0) {
            warnings.push("hotCorners." + name + ": unknown action " + JSON.stringify(action) + ", leaving the corner inert");
            corners[name] = "none";
            continue;
        }
        corners[name] = action;
    }
    return {
        enabled: raw.enabled === undefined ? true : raw.enabled === true,
        size: _clampedNumber(raw.size, DEFAULT_SIZE, 1, MAX_SIZE, "size", warnings),
        delayMs: _clampedNumber(raw.delayMs, DEFAULT_DELAY_MS, 0, MAX_DELAY_MS, "delayMs", warnings),
        corners: corners,
        warnings: warnings
    };
}

// The corner's two live layer-shell anchors. The other two stay false, and
// that is what makes PanelWindow size itself from implicitWidth/
// implicitHeight instead of stretching across the output.
function edges(corner) {
    return {
        top: corner === "topLeft" || corner === "topRight",
        bottom: corner === "bottomLeft" || corner === "bottomRight",
        left: corner === "topLeft" || corner === "bottomLeft",
        right: corner === "topRight" || corner === "bottomRight"
    };
}

// Flat {screen, corner, action} list — one entry per window HotCorners.qml
// actually has to create, so a corner left at "none" (or the whole feature
// switched off) costs no layer surface at all rather than a mapped but
// inert one holding an input region over live pixels.
function windows(config, screens) {
    var out = [];
    if (!config.enabled)
        return out;
    for (var s = 0; s < screens.length; s++) {
        for (var i = 0; i < CORNERS.length; i++) {
            var corner = CORNERS[i];
            if (config.corners[corner] === "none")
                continue;
            out.push({ screen: screens[s], corner: corner, action: config.corners[corner] });
        }
    }
    return out;
}
