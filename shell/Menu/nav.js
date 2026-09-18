.pragma library

// The launcher's cursor and keys (M72 T1), as pure functions over the row
// list Menu.qml commits: where the cursor lands when the rows change, where
// one key press moves it, and what a key means at all. Menu.qml holds the
// state and the views; everything here is testable without either.
//
// The cursor is a row id, and an index only as a consequence of where that
// id sits in the rows on screen. Rows change for more reasons than typing (a
// `when` condition resolving after the open, the clipboard or the window
// list ticking, the keybinds table landing), and an index held across such a
// change points at whatever row slid into its slot.

// Where the cursor goes when the row list becomes `ids`. `fresh` is a new
// query, level or open, which always starts on the first row, and `placed`
// is whether a key or the pointer has moved the cursor since: until one
// has, the cursor is the list's head rather than any particular row, and it
// stays on the first row while rows keep arriving above the one it started
// on (the `when` conditions an open resolves a moment later). Once placed,
// the row it was put on (`wantId`) keeps it wherever that row now sits, and
// while that row is gone the cursor holds `prevIndex`, clamped to the list,
// until the row comes back or a key puts the cursor somewhere else.
function rederive(wantId, prevIndex, ids, fresh, placed) {
    var n = ids.length;
    if (n === 0 || fresh || !placed)
        return 0;
    if (wantId !== "") {
        var at = ids.indexOf(wantId);
        if (at >= 0)
            return at;
    }
    return Math.max(0, Math.min(n - 1, prevIndex));
}

// One key's move over a list whose first `cells` entries are a grid of
// `columns` and whose rest are rows under it: `cells` is the whole list for
// the picker and emoji grids, 0 for a row list, the app count for the app
// grid. Returns the new index and whether the move travels (a step) or
// snaps (a wrap, a page, an end), which is what the cursor fill animates on.
//
// Vertical moves keep the column: off the bottom of the grid onto the top
// row of the same column, off the top onto the last row that has one, so a
// short last row never swallows the column. Out of the grid's last row the
// cursor goes to the first row under it, and up out of that row back to the
// last cell. Horizontal moves walk the list in reading order and stop at
// either end rather than wrapping, since Left on the first result has
// nowhere a reader would expect.
function step(index, dir, count, cells, columns, page) {
    var n = count;
    if (n <= 0)
        return { index: 0, travels: false };
    var i = Math.max(0, Math.min(n - 1, index));
    var g = Math.max(0, Math.min(n, cells));
    var c = g > 0 ? Math.max(1, columns) : 1;
    var tail = g < n;

    switch (dir) {
    case "home":
        return { index: 0, travels: false };
    case "end":
        return { index: n - 1, travels: false };
    case "pageDown":
        return { index: Math.min(n - 1, i + Math.max(1, page)), travels: false };
    case "pageUp":
        return { index: Math.max(0, i - Math.max(1, page)), travels: false };
    case "left":
        return i > 0 ? { index: i - 1, travels: true } : { index: i, travels: false };
    case "right":
        return i < n - 1 ? { index: i + 1, travels: true } : { index: i, travels: false };
    case "down":
        if (i < g) {
            var lastRowStart = Math.floor((g - 1) / c) * c;
            if (i < lastRowStart)
                return { index: Math.min(i + c, g - 1), travels: true };
            if (tail)
                return { index: g, travels: true };
            return { index: i % c, travels: false };
        }
        if (i + 1 < n)
            return { index: i + 1, travels: true };
        return { index: 0, travels: false };
    case "up":
        if (i < g) {
            if (i - c >= 0)
                return { index: i - c, travels: true };
            if (tail)
                return { index: n - 1, travels: false };
            return { index: lastInColumn(i % c, g, c), travels: false };
        }
        if (i - 1 >= g)
            return { index: i - 1, travels: true };
        if (g > 0)
            return { index: g - 1, travels: true };
        return { index: n - 1, travels: false };
    }
    return { index: i, travels: false };
}

// The lowest cell in `column` of a grid of `cells`: the last row's own cell
// when that row reaches the column, the row above it when it is short.
function lastInColumn(column, cells, columns) {
    var at = Math.floor((cells - 1) / columns) * columns + column;
    return at > cells - 1 ? at - columns : at;
}

// What a key press in the search field means. Everything answering "pass"
// is left to the field itself, which is what makes Ctrl+Left/Right move the
// caret by word and Ctrl+Backspace delete one while the arrows belong to the
// results. `ctx`:
//   mode       "menu" | "select" | "input"
//   query      the field holds text
//   grid       the level's view is a grid, so Left/Right move between cells
//   appView    an app view owns the body (it scrolls rather than moving a row)
//   scrollable that app view declared something to scroll
//   variants   the picker's Dark | Light switcher is up
function keyAction(key, modifiers, autoRepeat, ctx) {
    var ctrl = (modifiers & Qt.ControlModifier) !== 0;
    var shift = (modifiers & Qt.ShiftModifier) !== 0;
    var alt = (modifiers & Qt.AltModifier) !== 0;
    var plain = !ctrl && !shift && !alt;

    switch (key) {
    case Qt.Key_Up:
        return ctx.appView ? "scrollUp" : "up";
    case Qt.Key_Down:
        return ctx.appView ? "scrollDown" : "down";
    case Qt.Key_Left:
        return plain && ctx.grid && !ctx.appView ? "left" : "pass";
    case Qt.Key_Right:
        return plain && ctx.grid && !ctx.appView ? "right" : "pass";
    case Qt.Key_PageUp:
        if (ctx.appView)
            return ctx.scrollable ? "scrollPageUp" : "pass";
        return ctx.mode === "input" ? "pass" : "pageUp";
    case Qt.Key_PageDown:
        if (ctx.appView)
            return ctx.scrollable ? "scrollPageDown" : "pass";
        return ctx.mode === "input" ? "pass" : "pageDown";
    case Qt.Key_Home:
        if (ctx.appView)
            return ctx.scrollable && plain ? "scrollHome" : "pass";
        return plain && ctx.mode !== "input" ? "home" : "pass";
    case Qt.Key_End:
        if (ctx.appView)
            return ctx.scrollable && plain ? "scrollEnd" : "pass";
        return plain && ctx.mode !== "input" ? "end" : "pass";
    case Qt.Key_Return:
    case Qt.Key_Enter:
        if (ctx.mode === "input")
            return "submit";
        return shift ? "activateAlternate" : "activate";
    case Qt.Key_Escape:
        if (ctx.mode === "input")
            return "close";
        if (ctx.query)
            return "clear";
        return ctx.mode === "menu" ? "pop" : "close";
    case Qt.Key_Backspace:
        if (ctx.query || ctx.mode !== "menu")
            return "pass";
        // One level per physical press: a held key repeats, and a repeat
        // that outlived the text it was deleting would walk the whole tree
        // and close the launcher.
        return autoRepeat ? "swallow" : "pop";
    case Qt.Key_Tab:
    case Qt.Key_Backtab:
        return ctx.variants ? "variant" : "swallow";
    }
    return "pass";
}
