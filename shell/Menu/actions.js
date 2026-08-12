.pragma library

// The launcher's bottom action bar (M23) — Raycast's footer translated into
// this shell's own ledger language: what Enter does to the row under the
// cursor on the left, the keys that always apply on the right. Pure data,
// so the verb a row answers to is decided in exactly one place and a test
// can reach it; Menu.qml owns the state and MenuActionBar.qml paints it.
//
// Verbs come from a node's `kind` (plus `typeText`, the emoji rows' own
// copy-and-type marker), never from its id — a verb keyed off an id prefix
// would go quietly wrong the first time a provider renamed its rows. A row
// that can't be activated at all (`dim: true`, the honest-empty note rows
// every provider falls back to) gets no primary action rather than a verb
// that would do nothing when pressed.
//
// Key caps are literal characters, not names, and every one of them is
// checked against the pinned nerd-fonts-jetbrains-mono cmap: U+23CE ⏎ is
// present, U+21B5 ↵ — the more obvious return glyph — is NOT, and would
// render as tofu. Escape stays the word "ESC" for the same reason its
// U+238B symbol is unhelpful even where it exists.
var KEY_ENTER = "⏎";
var KEY_UPDOWN = "↑↓";
var KEY_GRID = "←→↑↓";
var KEY_ESC = "ESC";

// `ctx`: { mode, node, atRoot, grid, pickerSelect, confirming }.
function primaryAction(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return { key: KEY_ENTER, label: "Submit" };
    var node = c.node;
    if (!node || node.dim === true)
        return null;
    if (c.confirming)
        return { key: KEY_ENTER, label: "Confirm " + node.label };
    switch (node.kind) {
    case "option":
        return { key: KEY_ENTER, label: "Select" };
    case "image":
        return { key: KEY_ENTER, label: c.pickerSelect ? "Choose" : "Set Wallpaper" };
    case "app":
        return { key: KEY_ENTER, label: "Open" };
    case "submenu":
    case "provider":
    case "link":
        return { key: KEY_ENTER, label: "Enter" };
    case "action":
        if (node.typeText)
            return { key: KEY_ENTER, label: "Copy And Type" };
        return { key: KEY_ENTER, label: "Run" };
    }
    return null;
}

// The keys that always apply, right-aligned. Escape reads BACK wherever
// there is a level to pop and CLOSE at the root, because those are two
// genuinely different outcomes and guessing wrong is the whole reason a
// hint bar exists.
function hints(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return [{ key: KEY_ESC, label: "Cancel" }];
    var move = { key: c.grid ? KEY_GRID : KEY_UPDOWN, label: "Move" };
    if (c.mode === "select")
        return [move, { key: KEY_ESC, label: "Cancel" }];
    return [move, { key: KEY_ESC, label: c.atRoot ? "Close" : "Back" }];
}

function actionBar(ctx) {
    return { primary: primaryAction(ctx), hints: hints(ctx) };
}
