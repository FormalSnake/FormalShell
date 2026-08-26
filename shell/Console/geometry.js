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
// never the output mode's physical pixels). `insets` is Theme.edgeInset, the
// exclusive zone the bar already took off its own edge; the console drops
// from the top of what is left and covers `share` of its height, full width
// less one margin either side.
function consoleGeometry(screen, insets, share, margin) {
    if (!screen || !(screen.width > 0) || !(screen.height > 0))
        return null;
    var bar = insets || { top: 0, bottom: 0, left: 0, right: 0 };
    var gap = Math.max(0, Math.round(margin || 0));
    var top = Math.round(screen.y + Math.max(0, bar.top) + gap);
    var usable = screen.height - Math.max(0, bar.top) - Math.max(0, bar.bottom) - gap;
    // A margin wider than the screen is a config mistake, not a reason to
    // hand the compositor a negative box.
    var width = Math.max(1, Math.round(screen.width - Math.max(0, bar.left) - Math.max(0, bar.right) - gap * 2));
    var height = Math.max(1, Math.round(usable * clampShare(share)) - gap);
    return {
        x: Math.round(screen.x + Math.max(0, bar.left) + gap),
        y: top,
        width: width,
        height: height
    };
}
