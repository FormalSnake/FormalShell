.pragma library

// Which output animates. One does; every other screen paints the finished
// banner once and never repaints.
//
// A frame of the animation is a full-screen Canvas repaint, and Qt 6's
// Canvas can only render into a QImage, so each one costs a CPU rasterize
// plus a whole-surface texture upload (16 MB at 2560x1600). On a hybrid
// laptop the outputs are split across two cards — the panel on the iGPU, an
// external head on the dGPU — while the shell renders on one device for all
// of its surfaces, so every frame on an output the compositor doesn't scan
// out locally is also a cross-GPU copy. Animating one screen instead of all
// of them is the only lever the client has over that.
//
// `screensaver.outputPriority` names which one, in preference order:
//
//     "screensaver": { "outputPriority": ["HDMI", "internal"] }
//
// First entry with a connected output wins, so that list reads "the desk
// monitor when it's plugged in, the laptop panel when it isn't". An entry
// matches a connector by exact name ("HDMI-A-1"), by the port it hangs off
// ("HDMI", "DP-2"), or by one of the two aliases below. Unset — the default
// — falls through to the focused output, which on a single-head session is
// the only output there is.

// Connectors the panel built into the machine shows up as.
var INTERNAL_PREFIXES = ["edp", "lvds", "dsi"];

// (names, priority, focused, current) -> the name to animate, "" only when
// there are no outputs at all.
//
// A configured priority wins outright, and is re-applied on every screen
// change: plugging the main monitor back in mid-run hands the animation to
// it, which is the whole point of naming it first.
//
// `current` only holds the line for an unconfigured session. There the
// answer comes from focus, which says nothing new once the session is
// already idle, so a screen arriving must not drag the animation off the
// output it started on — restarting ttfx there would replay the effect from
// frame 0 on a screen already past it. An unplug still moves it: the name is
// gone from `names`, so the fallbacks below pick up.
function resolveMainOutput(names, priority, focused, current) {
    var preferred = matchPriority(names, priority);
    if (preferred)
        return preferred;
    if (contains(names, current))
        return current;
    if (contains(names, focused))
        return focused;
    return names.length > 0 ? names[0] : "";
}

// The first entry in the priority list with a connected output, or "" —
// which is also how a list of nothing but typos and unplugged monitors
// answers, so Screensaver.qml can say so once rather than silently
// animating somewhere else.
function matchPriority(names, priority) {
    var entries = priorityList(priority);
    for (var i = 0; i < entries.length; i++) {
        var hit = matchEntry(names, entries[i]);
        if (hit)
            return hit;
    }
    return "";
}

// One entry -> the connector it names, or "".
//
// Exact before prefix: an "HDMI-A-1" in the list is answered by that
// connector even on a machine where "HDMI-A-2" sorts first.
function matchEntry(names, entry) {
    var wanted = String(entry || "").toLowerCase();
    if (wanted.length === 0)
        return "";
    var i;
    for (i = 0; i < names.length; i++) {
        if (names[i].toLowerCase() === wanted)
            return names[i];
    }
    if (wanted === "internal" || wanted === "external") {
        var wantInternal = wanted === "internal";
        for (i = 0; i < names.length; i++) {
            if (isInternal(names[i]) === wantInternal)
                return names[i];
        }
        return "";
    }
    // Anchored, so "DP" names the DisplayPort outputs and not the "eDP" the
    // laptop panel hangs off.
    for (i = 0; i < names.length; i++) {
        if (names[i].toLowerCase().indexOf(wanted) === 0)
            return names[i];
    }
    return "";
}

function isInternal(name) {
    var lower = String(name || "").toLowerCase();
    for (var i = 0; i < INTERNAL_PREFIXES.length; i++) {
        if (lower.indexOf(INTERNAL_PREFIXES[i]) === 0)
            return true;
    }
    return false;
}

// settings.json is hand-written, so a single output named as a bare string
// is a likelier mistake than a considered one. Read it as a one-entry list
// instead of ignoring the whole key.
function priorityList(value) {
    if (typeof value === "string")
        return value.length > 0 ? [value] : [];
    if (!value || value.length === undefined)
        return [];
    return value;
}

function contains(names, name) {
    if (!name)
        return false;
    for (var i = 0; i < names.length; i++) {
        if (names[i] === name)
            return true;
    }
    return false;
}

// Quickshell.screens -> plain names, so everything above stays a function of
// strings and testable without a compositor.
function screenNames(screens) {
    var names = [];
    for (var i = 0; i < screens.length; i++)
        names.push(screens[i].name);
    return names;
}
