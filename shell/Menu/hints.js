.pragma library

// The launcher row's right-aligned hint (M48 D6), shadcn's `CommandShortcut`
// slot: the chord that summons this route directly, or how many rows the
// route holds, or nothing at all.
//
// The chords are a table here rather than a parse of
// docs/examples/hyprland/formalshell.conf at runtime: that file is an
// EXAMPLE the reader copies and edits, so what it says is what the shipped
// bindings are, not what any given session actually has bound. Reading a
// user's live `hyprctl binds` instead would be honest about one session and
// wrong about the row's identity (two chords can summon one route, a submap
// can shadow one), and it would put a process behind a per-row property.
// tests/tst_menu_hints.qml derives the same table from that conf and fails
// when the two drift, which is what keeps this honest without a runtime
// dependency.
//
// Written the way a reader would type them (`Super+Ctrl+E`), not in
// Hyprland's own uppercase (`SUPER+CTRL+E`): the launcher renders them as a
// value in mono, and DESIGN.md §5 leaves uppercase to section labels and the
// breadcrumb.
var ROUTE_CHORDS = {
    "apps": "Super+Alt+Space",
    "calc": "Super+Ctrl+Q",
    "capture": "Super+Ctrl+C",
    "clipboard": "Super+Ctrl+V",
    "emoji": "Super+Ctrl+E",
    "keybinds": "Super+K",
    "reminder": "Super+Ctrl+R",
    "share": "Super+Ctrl+S",
    "system": "Super+Escape",
    "theme": "Super+Shift+Ctrl+Space",
    "toggles": "Super+Ctrl+O",
    "wallpaper": "Super+Ctrl+Space"
};

function chordFor(id) {
    return ROUTE_CHORDS[String(id || "")] || "";
}

// A count only for a "provider" node, which is the kind whose children are
// a LISTING (installed apps, clipboard entries, tray items, cards). A plain
// submenu's children are a handful of named commands the row beside them
// already spells out, so a number there is noise rather than information.
// Zero reads as no hint at all: a provider whose backend has nothing to
// list says so in its own empty row, not in a "(0)" beside the route.
function countFor(node) {
    if (!node || node.kind !== "provider")
        return "";
    var n = (node.childIds || []).length;
    return n > 0 ? String(n) : "";
}

// The chord wins: it is the row's own accelerator, and a reader who learns
// it stops opening the launcher to reach that route at all.
function hintFor(node) {
    if (!node)
        return "";
    var chord = chordFor(node.id);
    return chord !== "" ? chord : countFor(node);
}
