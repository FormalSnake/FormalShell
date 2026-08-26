.pragma library

// Panel.qml's frame geometry, as pure functions (DESIGN.md §1 "Padding",
// M48 D3). Panel holds the screen and the tokens as QML properties so
// surfaces can bind to them; the arithmetic lives here so it is testable
// without the Quickshell types Panel.qml pulls in, the same split cursor.js
// and tokens.js already use.

// Where the frame's left edge sits. `anchorX` is the bar cell that opened
// the panel, or a negative number for an IPC open with no cell, which falls
// back to the right edge. Either way the frame is held one `screenPadding`
// in from both side edges; a panel wider than the screen minus both paddings
// gives up the right clamp rather than being pushed off the left edge.
function frameX(anchorX, screenWidth, panelWidth, screenPadding) {
    var right = screenWidth - panelWidth - screenPadding;
    var x = anchorX >= 0 ? anchorX : right;
    return Math.max(screenPadding, Math.min(x, Math.max(screenPadding, right)));
}

// The tallest the frame may be: the screen minus the bar, the `barMargin` it
// hangs off the bar by, and one `screenPadding` above the bottom edge.
function maxFrameHeight(screenHeight, barHeight, barMargin, screenPadding) {
    return Math.max(0, screenHeight - barHeight - barMargin - screenPadding);
}

// What is left of that for the content column once the card's own padding,
// its header row and the gap under the header have taken their share.
// Content taller than this scrolls.
function maxContentHeight(maxFrame, panelPadding, headerHeight, sectionGap) {
    return Math.max(0, maxFrame - panelPadding * 2 - headerHeight - sectionGap);
}

// The frame's own height: its chrome plus whatever the content asked for,
// capped.
function frameHeight(contentHeight, maxContent, panelPadding, headerHeight, sectionGap) {
    return panelPadding * 2 + headerHeight + sectionGap + Math.min(contentHeight, maxContent);
}
