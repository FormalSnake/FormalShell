.pragma library

// Which output animates. One does; every other screen paints the finished
// banner once and never repaints.
//
// A frame of the animation is a full-screen Canvas repaint, and Qt 6's
// Canvas can only render into a QImage, so each one costs a CPU rasterize
// plus a whole-surface texture upload (16 MB at 2560x1600). On a hybrid
// laptop the outputs are split across two cards — here eDP on the iGPU, the
// external head on the dGPU — while the shell renders on one device for all
// of its surfaces, so every frame on an output the compositor doesn't scan
// out locally is also a cross-GPU copy. Animating one screen instead of all
// of them is the only lever the client has over that.
//
// The focused output is the main one: the screensaver comes up on an idle
// session, so focus is wherever the session was last actually being used,
// and no input can move it while the surfaces are up.

// (names, focused, current) -> the name to animate, "" only when there are no
// outputs at all.
//
// `current` wins whenever it is still connected. Re-resolving happens on
// every screen change, and plugging a second monitor in mid-run must not
// move the animation off the screen it started on — restarting ttfx there
// would replay the effect from frame 0 on a screen already past it. An
// unplug is the case that does move it: the name is gone from `names`, so
// the fallbacks below pick up.
function resolveMainOutput(names, focused, current) {
    if (contains(names, current))
        return current;
    if (contains(names, focused))
        return focused;
    return names.length > 0 ? names[0] : "";
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

// Quickshell.screens -> plain names, so the resolver above stays a function
// of strings and testable without a compositor.
function screenNames(screens) {
    var names = [];
    for (var i = 0; i < screens.length; i++)
        names.push(screens[i].name);
    return names;
}
