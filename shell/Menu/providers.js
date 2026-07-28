.pragma library

// Provider functions populate a "provider" kind node's children at
// tree-build time (Model.buildTree() infers "provider" from an entry's
// `provider` key — see default-menu.jsonc's "apps" node). Providers return
// ready-made Node fragments (Model's Node shape: id/label/icon/title/
// aliases/kind/childIds) rather than JSONC entries, because they bypass
// buildTree()'s action/target/provider kind inference entirely — an app has
// no `action` string, it has a DesktopEntry to call execute() on, which
// respects .desktop field codes/Exec quoting that re-running it through
// `sh -c` would mangle.

// `entries` = DesktopEntries.applications.values (Quickshell's built-in
// desktop-entry index, already excludes Hidden/NoDisplay). Each app node
// keeps a reference to its DesktopEntry (`_entry`) so Menu.qml's activation
// can call `_entry.execute()` directly instead of spawning a shell command.
function appsProvider(entries) {
    return (entries || []).map(function (entry) {
        return {
            id: "apps." + entry.id,
            parentId: null,
            label: entry.name,
            icon: entry.icon || "",
            title: entry.genericName || "",
            aliases: [],
            kind: "app",
            childIds: [],
            _entry: entry
        };
    });
}

// Merges every "provider" node's produced children into `tree` (a
// Model.buildTree() result): for each provider node, looks up its
// `provider` name in `providerFns` (name -> fn(): [Node]), parents the
// returned nodes under it, and registers them in `tree.nodes`. Mutates and
// returns `tree`.
function applyProviders(tree, providerFns) {
    Object.keys(tree.nodes).forEach(function (id) {
        var node = tree.nodes[id];
        if (node.kind !== "provider") return;
        var fn = providerFns[node.provider];
        if (!fn) return;
        fn().forEach(function (child) {
            child.parentId = node.id;
            tree.nodes[child.id] = child;
            node.childIds.push(child.id);
        });
    });
    return tree;
}

// Clipboard history rows, newest first (ClipboardService.items' own order).
// Unlike appsProvider these are plain "action" nodes — Menu.qml's existing
// `_activateRow`/`_runAction` spawn-command path already re-copies the entry
// via `qs ipc call clipboard copy <id>` with zero Menu.qml changes, so no
// bespoke node kind (and no `_entry`-style back-reference) is needed here.
function clipboardProvider(items) {
    return (items || []).map(function (entry) {
        return {
            id: "clipboard." + entry.id,
            parentId: null,
            label: previewLabel(entry.text),
            icon: "",
            title: "",
            aliases: [],
            kind: "action",
            action: "qs ipc call clipboard copy " + entry.id,
            childIds: []
        };
    });
}

// First non-blank line only, capped at maxLen chars — clipboard captures can
// be multi-line/arbitrarily long, and MenuRow's label is a single Text with
// no wrapping, so anything longer needs pre-truncating here rather than
// spilling into the ledger row below it.
function previewLabel(text, maxLen) {
    maxLen = maxLen || 60;
    var lines = text.split("\n");
    var firstLine = "";
    for (var i = 0; i < lines.length; i++) {
        var trimmed = lines[i].trim();
        if (trimmed !== "") { firstLine = trimmed; break; }
    }
    if (firstLine === "") firstLine = text.trim();
    var truncated = firstLine.length > maxLen;
    var out = truncated ? firstLine.slice(0, maxLen) : firstLine;
    return (truncated || lines.length > 1) ? out + "…" : out;
}

// Expands Config's `menu.customPowerButtons` (the spec's "first-class, not
// a workaround" case — e.g. an owner's Windows-reboot bootloader shortcut)
// into JSONC-shaped entry fragments keyed by dotted id, meant to be merged
// into the default tree object before Model.buildTree() runs:
// `system.custom.<i>` auto-nests under the already-declared `system` node
// exactly like any other dotted id.
function customPowerButtonEntries(buttons) {
    var out = {};
    (buttons || []).forEach(function (btn, i) {
        out["system.custom." + i] = {
            label: btn.label,
            icon: btn.icon || "",
            action: btn.command,
            confirm: btn.confirm === true
        };
    });
    return out;
}
