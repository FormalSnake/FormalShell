.pragma library

// The launcher's bottom action bar (M23), Raycast's footer translated into
// this shell's own ledger language: what Enter does to the row under the
// cursor on the left, the keys that always apply on the right. Pure data,
// so the verb a row answers to is decided in exactly one place and a test
// can reach it; Menu.qml owns the state and views/MenuFooter.qml paints it.
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
// Keys are names, one per cap (Components/keys.js spells them and turns
// the arrows into icons), so a legend never depends on which glyphs the
// `monospace` face happens to carry. `keys` is a list: a chord's keys, or
// the keys a legend offers side by side.
var KEY_ENTER = ["Enter"];
var KEY_ESC = ["Esc"];
var KEY_TAB = ["Tab"];
var KEY_SHIFT_ENTER = ["Shift", "Enter"];

// `ctx`: { mode, node, atRoot, pickerSelect, variantSwitch, confirming,
// discreteGpu, clipsshImage }.
function primaryAction(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return { keys: KEY_ENTER, label: "Submit" };
    var node = c.node;
    if (!node || node.dim === true)
        return null;
    if (c.confirming)
        return { keys: KEY_ENTER, label: "Confirm " + node.label };
    if (node.verb)
        return { keys: KEY_ENTER, label: node.verb };
    switch (node.kind) {
    case "option":
        return { keys: KEY_ENTER, label: "Select" };
    case "image":
        return { keys: KEY_ENTER, label: c.pickerSelect ? "Choose" : "Set wallpaper" };
    case "app":
        return { keys: KEY_ENTER, label: "Open" };
    case "submenu":
    case "provider":
    case "link":
        return { keys: KEY_ENTER, label: "Open" };
    case "action":
        return { keys: KEY_ENTER, label: "Run" };
    }
    return null;
}

// The keys that apply beside Enter, right-aligned after its verb. The
// arrows are not among them: every level moves on them, and four caps for
// the one thing every list does crowd out the verbs a reader does not
// already know. Escape reads BACK wherever
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
// different from Enter (Menu.qml's _activateRowAlternate). It is a per-row
// hint rather than an always-applies one, so it appears only with the cursor
// on an app: the offload used to be advertised as a route listing every app
// a second time, and this is what replaced it.
//
// `clipsshImage` is the other row kind Shift+Enter answers to: a clipboard
// image, sent over ssh instead of copied. Ungated on aliases existing, since
// with none saved the key drills into the route whose empty state spells out
// the add command, which is a better answer than a hint that isn't there.
function hints(ctx) {
    var c = ctx || {};
    if (c.mode === "input")
        return [{ keys: KEY_ESC, label: "Cancel" }];
    var out = [];
    if (c.variantSwitch === "dark" || c.variantSwitch === "light")
        out.push({ keys: KEY_TAB, label: c.variantSwitch === "light" ? "Show light" : "Show dark" });
    if (c.discreteGpu && c.node && c.node.kind === "app" && !c.confirming)
        out.push({ keys: KEY_SHIFT_ENTER, label: "Open on GPU" });
    if (c.clipsshImage && !c.confirming)
        out.push({ keys: KEY_SHIFT_ENTER, label: "Send over SSH" });
    if (c.mode === "select")
        return out.concat([{ keys: KEY_ESC, label: "Cancel" }]);
    return out.concat([{ keys: KEY_ESC, label: c.atRoot ? "Close" : "Back" }]);
}

function actionBar(ctx) {
    return { primary: primaryAction(ctx), hints: hints(ctx) };
}
