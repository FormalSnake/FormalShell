.pragma library

// Panel.qml's keyboard cursor, as pure functions (spec "Keyboard model").
// Panel holds the state as QML properties so surfaces can bind to it; the
// arithmetic lives here so it is testable without the Quickshell types
// Panel.qml pulls in, the same split tokens.js and Bar/layout.js already use.

function clamp(index, count) {
    if (count <= 0)
        return 0;
    return Math.max(0, Math.min(count - 1, index));
}

// The first navigation key only reveals the cursor where it already sits
// (upstream's CursorSurface contract): the highlight has to appear somewhere
// the eye can find it before anything under it moves. Vertical wins over
// horizontal so one call covers both axes of a single-column list.
function move(index, count, active, dx, dy) {
    if (!active)
        return { index: clamp(index, count), active: true };
    var delta = dy !== 0 ? dy : dx;
    return { index: clamp(index + delta, count), active: true };
}

// What activateCursor() reports, or -1 for nothing to activate. A section
// past the row list (a panel footer holding one button) carries no rows of
// its own, so only section 0 is gated on the row count.
function activation(index, count, active, section) {
    if (!active)
        return -1;
    if (section > 0)
        return clamp(index, count);
    return count > 0 ? clamp(index, count) : -1;
}

// Tab wraps through the panel's sections in either direction.
function section(current, count, direction) {
    if (count <= 1)
        return 0;
    return ((current + direction) % count + count) % count;
}

// The panel's KeyCatcher takes no keys at all while an inline editor holds
// focus, nor while the panel is closed but still mapped (Panel's
// `keepMapped`), where a stray key would drive a surface nobody can see.
function catcherBlocked(isOpen, inlineEditorFocused) {
    return !isOpen || !!inlineEditorFocused;
}
