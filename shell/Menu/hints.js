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
// value in mono, and a chord is a key combination, never a section heading.
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

// What a route answers to when typed as a prefix from any level
// (providers.js's emojiTriggerQuery and nixTriggerQuery, keybinds.js's
// triggerQuery): the shortest way to it, so it outranks the chord.
var ROUTE_PREFIXES = {
    "emoji": ":e",
    "nix": ":nix",
    "keybinds": ":k"
};

// The launcher row's accessory, right-aligned and muted (M72 T4): the row's
// own value when it carries one, otherwise what the row is. An app says so;
// a route says how to reach it without the launcher's tree, by prefix, by
// chord or by how many rows it holds; a runnable row is a command. A row
// whose provider names its own verb (a clipboard entry, an emoji) is
// content rather than a command, and like a note or an option it carries
// nothing its own label does not already say.
function accessoryFor(node) {
    if (!node)
        return "";
    if ((node.meta || "") !== "")
        return String(node.meta);
    switch (node.kind) {
    case "app":
        return "Application";
    case "action":
        return node.verb ? "" : "Command";
    case "submenu":
    case "provider":
    case "link":
        return ROUTE_PREFIXES[String(node.id || "")] || hintFor(node);
    }
    return "";
}

// The accessory as the keys of a chord, one per cap, when that is what it
// is: a route's summoning chord. Empty for every other accessory, which
// stays a word or a value.
function chordKeysFor(node) {
    if (!node)
        return [];
    var chord = chordFor(node.id);
    if (chord === "" || accessoryFor(node) !== chord)
        return [];
    return chord.split("+");
}
