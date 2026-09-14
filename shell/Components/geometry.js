.pragma library

// Panel.qml's frame geometry, as pure functions (DESIGN.md §1 "Padding",
// M48 D3). Panel holds the screen and the tokens as QML properties so
// surfaces can bind to them; the arithmetic lives here so it is testable
// without the Quickshell types Panel.qml pulls in, the same split cursor.js
// and tokens.js already use.
//
// A panel hangs off the bar, `barMargin` from the bar's inner edge, and
// sits along the bar centred on the cell that opened it. `barPosition` says
// which edge that is; `insets` is Theme.edgeInset, the bar's thickness on its own
// edge and 0 elsewhere.

function _vertical(barPosition) {
    return barPosition === "left" || barPosition === "right";
}

// Where the frame starts along the bar. `anchor` is the along-axis centre
// of the bar cell that opened the panel, or a negative number for an IPC
// open with no cell, which falls back to the end of the bar (the right
// region, where every widget cell lives). A cell-anchored frame is centred
// on its cell, the same placement Tooltip.qml gives its own card. Either
// way the frame is held one `screenPadding` in from whatever the two ends
// already give up (`insetStart`/`insetEnd`, the screen frame's band when
// there is one); a panel longer than the room between gives up the far
// clamp rather than being pushed off the near edge.
function frameAlong(anchor, screenExtent, frameExtent, insetStart, insetEnd, screenPadding) {
    var near = insetStart + screenPadding;
    var far = screenExtent - insetEnd - frameExtent - screenPadding;
    var at = anchor >= 0 ? anchor - frameExtent / 2 : far;
    return Math.max(near, Math.min(at, Math.max(near, far)));
}

// Top or bottom bar: x along the bar, y off its inner edge.
function frameX(barPosition, anchorX, screenWidth, panelWidth, insets, barMargin, screenPadding) {
    if (barPosition === "left")
        return insets.left + barMargin;
    if (barPosition === "right")
        return screenWidth - insets.right - barMargin - panelWidth;
    return frameAlong(anchorX, screenWidth, panelWidth, insets.left, insets.right, screenPadding);
}

// Left or right bar: y along the bar, x off its inner edge.
function frameY(barPosition, anchorY, screenHeight, frameHeight, insets, barMargin, screenPadding) {
    if (barPosition === "bottom")
        return screenHeight - insets.bottom - barMargin - frameHeight;
    if (_vertical(barPosition))
        return frameAlong(anchorY, screenHeight, frameHeight, insets.top, insets.bottom, screenPadding);
    return insets.top + barMargin;
}

// The tallest the frame may be. Under a horizontal bar: the screen minus
// the bar, the `barMargin` it hangs off the bar by, and one `screenPadding`
// at the far edge. Beside a vertical bar the frame hangs off nothing above
// or below it, so only the two paddings (and the screen frame's band, when
// there is one) come off.
function maxFrameHeight(barPosition, screenHeight, insets, barMargin, screenPadding) {
    if (_vertical(barPosition))
        return Math.max(0, screenHeight - insets.top - insets.bottom - screenPadding * 2);
    return Math.max(0, screenHeight - insets.top - insets.bottom - barMargin - screenPadding);
}

// What is left of that for the content column once the card's own padding,
// its header row and the header's seam (the two gaps plus the rule itself)
// have taken their share. Content taller than this scrolls.
function maxContentHeight(maxFrame, panelPadding, headerHeight, headerGap) {
    return Math.max(0, maxFrame - panelPadding * 2 - headerHeight - headerGap);
}

// The frame's own height: its chrome plus whatever the content asked for,
// capped.
function frameHeight(contentHeight, maxContent, panelPadding, headerHeight, headerGap) {
    return panelPadding * 2 + headerHeight + headerGap + Math.min(contentHeight, maxContent);
}
