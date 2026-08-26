.pragma library

// Where the notification centre's card sits and how tall it gets (M48 D3).
// Pure, so the cap can be asserted without a compositor, the same split
// stack.js and Components/tooltip.js already use.
//
// The card hangs off the right edge one `padding` in, sits that same
// padding off the bar strip, and is as tall as its own content until that
// would cross the padding at the far edge, where it stops and the row list
// scrolls instead. Before M48 it was the full height between the bar and
// the bottom of the output whatever it held, which is what let a long
// history run off the screen. `insets` is Theme.edgeInset: the bar's
// thickness on its own edge and 0 on the other three, so a bottom bar
// pushes the card up and a right bar pushes it left.
function centerFrame(params) {
    var padding = params.padding;
    var insets = params.insets || { top: 0, bottom: 0, left: 0, right: 0 };
    var available = Math.max(0, params.screenHeight - insets.top - insets.bottom - padding * 2);
    var content = Math.max(0, params.contentHeight);
    var height = Math.min(content, available);

    return {
        // Clamped so a card wider than the output starts at the left
        // padding rather than off-screen, the same rule tooltip.js's own
        // placement uses.
        x: Math.max(insets.left + padding, params.screenWidth - insets.right - params.cardWidth - padding),
        // Off the bar on a top bar; on a bottom bar the card hangs up from
        // the bar instead, so a bell at the bottom opens the card above it.
        y: insets.bottom > 0
            ? params.screenHeight - insets.bottom - padding - height
            : insets.top + padding,
        height: height,
        // What the output leaves, reported alongside the height so the cap
        // can be read back over IPC rather than measured off a screenshot.
        available: available,
        capped: content > available
    };
}
