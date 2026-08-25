.pragma library

// Where the quake console lands. Pure, so the placement is testable without
// a compositor (tests/tst_console_geometry.qml).
//
// Resolved on every show rather than once at spawn: a window rule sized at
// first map freezes the console at whatever the screen measured that day,
// and an output rescaled afterwards leaves a console that is no longer half
// of anything (omarchy hit this and worked around it with a gap rule,
// default/hypr/qconsole.lua).

var SHARE_MIN = 0.2;
var SHARE_MAX = 1.0;

function clampShare(share) {
    var value = Number(share);
    if (!isFinite(value))
        return 0.5;
    return Math.min(SHARE_MAX, Math.max(SHARE_MIN, value));
}

// `screen` is the output's LOGICAL box ({x, y, width, height}, Quickshell.
// screens, the same space windows[].rect and the placement dispatchers use,
// never the output mode's physical pixels). `barHeight` is the exclusive
// zone the bar already took off the top; the console covers `share` of what
// is left under it, full width less one margin either side.
function consoleGeometry(screen, barHeight, share, margin) {
    if (!screen || !(screen.width > 0) || !(screen.height > 0))
        return null;
    var gap = Math.max(0, Math.round(margin || 0));
    var top = Math.round(screen.y + Math.max(0, barHeight || 0) + gap);
    var usable = screen.height - Math.max(0, barHeight || 0) - gap;
    // A margin wider than the screen is a config mistake, not a reason to
    // hand the compositor a negative box.
    var width = Math.max(1, Math.round(screen.width - gap * 2));
    var height = Math.max(1, Math.round(usable * clampShare(share)) - gap);
    return {
        x: Math.round(screen.x + gap),
        y: top,
        width: width,
        height: height
    };
}
