.pragma library

// The launcher's bottom action bar (M23), Raycast's footer translated into
// this shell's own ledger language: what Enter does to the row under the
// cursor on the left, the keys that always apply on the right. Pure data,
// so the verb a row answers to is decided in exactly one place and a test
// can reach it; Menu.qml owns the state and MenuActionBar.qml paints it.
//
// Verbs come from a node's `kind`, never from its id: a verb keyed off an
// id prefix would go quietly wrong the first time a provider renamed its
// rows. A provider that knows better than `kind` does says so in the node's
// own `verb` field (clipboard and emoji rows: Copy, Paste or Share, none of
// which is "Run"); that stays row data for the same reason, so the verb has
// exactly one source per row. A row that can't be activated at all
// (`dim: true`, the honest-empty note rows every provider falls back to)
// gets no primary action rather than a verb that would do nothing when
// pressed.
//
// Key caps are literal characters, not names, and every one of them is
// checked against the pinned nerd-fonts-jetbrains-mono cmap: U+23CE ⏎ is
// present, U+21B5 ↵, the more obvious return glyph, is NOT, and would
// render as tofu. Escape stays the word "ESC" for the same reason its
// U+238B symbol is unhelpful even where it exists.
var KEY_ENTER = "⏎";
var KEY_UPDOWN = "↑↓";
var KEY_GRID = "←→↑↓";
var KEY_ESC = "ESC";
// The word, for the same reason Escape is: U+21E5 ⇥ is absent from the pinned
// nerd-fonts-jetbrains-mono cmap and would render as tofu.
var KEY_TAB = "TAB";
// Spelt out for the same reason, and reusing the one return glyph already
// checked above: U+21E7 ⇧ is not in every font the `monospace` alias
// resolves to either.
var KEY_SHIFT_ENTER = "SHIFT \u23CE";

// `ctx`: { mode, node, atRoot, grid, pickerSelect, variantSwitch, confirming }.
function primaryAction(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return { key: KEY_ENTER, label: "Submit" };
    var node = c.node;
    if (!node || node.dim === true)
        return null;
    if (c.confirming)
        return { key: KEY_ENTER, label: "Confirm " + node.label };
    if (node.verb)
        return { key: KEY_ENTER, label: node.verb };
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
        return { key: KEY_ENTER, label: "Run" };
    }
    return null;
}

// The keys that always apply, right-aligned. Escape reads BACK wherever
// there is a level to pop and CLOSE at the root, because those are two
// genuinely different outcomes and guessing wrong is the whole reason a
// hint bar exists.
//
// `variantSwitch` is the wallpaper route's other variant ("dark"/"light")
// when its Dark/Light switcher is up, and null everywhere else, the hint
// names the set Tab would show rather than the key's mechanism, so it reads
// as the outcome the way every other label here does.
//
// `discreteGpu` is true when GpuService has a default discrete card, which
// is the only condition under which Shift+Enter on an app row does anything
// different from Enter (Menu.qml's _activateRowOnDiscreteGpu). It is a
// per-row hint rather than an always-applies one, so it appears only with
// the cursor on an app: the offload used to be advertised as a route
// listing every app a second time, and this is what replaced it.
function hints(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return [{ key: KEY_ESC, label: "Cancel" }];
    var move = { key: c.grid ? KEY_GRID : KEY_UPDOWN, label: "Move" };
    var out = [move];
    if (c.variantSwitch === "dark" || c.variantSwitch === "light")
        out.push({ key: KEY_TAB, label: c.variantSwitch === "light" ? "Show Light" : "Show Dark" });
    if (c.discreteGpu && c.node && c.node.kind === "app" && !c.confirming)
        out.push({ key: KEY_SHIFT_ENTER, label: "Open On GPU" });
    if (c.mode === "select")
        return out.concat([{ key: KEY_ESC, label: "Cancel" }]);
    return out.concat([{ key: KEY_ESC, label: c.atRoot ? "Close" : "Back" }]);
}

function actionBar(ctx) {
    return { primary: primaryAction(ctx), hints: hints(ctx) };
}
