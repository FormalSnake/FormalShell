.pragma library

// Where the notification centre's card sits and how tall it gets (M48 D3).
// Pure, so the cap can be asserted without a compositor, the same split
// stack.js and Components/tooltip.js already use.
//
// The card hangs off the right edge one `padding` in, sits that same
// padding below the bar strip, and is as tall as its own content until that
// would cross the padding above the bottom edge, where it stops and the row
// list scrolls instead. Before M48 it was the full height between the bar
// and the bottom of the output whatever it held, which is what let a long
// history run off the screen.
function centerFrame(params) {
    var padding = params.padding;
    var available = Math.max(0, params.screenHeight - params.barHeight - padding * 2);
    var content = Math.max(0, params.contentHeight);

    return {
        // Clamped so a card wider than the output starts at the left
        // padding rather than off-screen, the same rule tooltip.js's own
        // placement uses.
        x: Math.max(padding, params.screenWidth - params.cardWidth - padding),
        y: params.barHeight + padding,
        height: Math.min(content, available),
        // What the output leaves, reported alongside the height so the cap
        // can be read back over IPC rather than measured off a screenshot.
        available: available,
        capped: content > available
    };
}
