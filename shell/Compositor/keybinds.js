.pragma library

// Compositor keybinds -> menu rows. Pure, so the mapping and the ranking are
// testable head-on (tests/tst_keybinds.qml); the hyprctl process stays in the
// menu surface.
//
// The input is `hyprctl binds`, with hyprland's own sources and submaps
// already expanded, so there is no include chain to walk here. Nothing
// throws: unreadable output yields an empty list, which the surface renders
// as an honest unavailable row rather than a warning.
//
// A Bind is:
//   { chord: "SUPER+SHIFT+slash", mods: ["SUPER", "SHIFT"], key: "slash",
//     action: "exec", args: ["qs ipc call menu toggle"], title: "",
//     props: { submap: "", catchall: "false" } }

var KEYBINDS_CHORD_PAD_MAX = 24;
var KEYBINDS_MAX_RESULTS = 200;

// Chords are padded into a column with U+00A0, not ASCII space: a Text
// item's implicit width drops trailing ASCII whitespace, so a space-padded
// label would measure as the bare chord and the column would collapse.
var _PAD_CHAR = "\u00a0";

// wlroots' modifier bits (WLR_MODIFIER_*, the table hyprland's
// stringToModMask writes), listed in the order a chord is conventionally
// written rather than in bit order, so 65 reads "SUPER+SHIFT" and not
// "SHIFT+SUPER".
var _HYPR_MODS = [
    [64, "SUPER"],
    [4, "CTRL"],
    [8, "ALT"],
    [1, "SHIFT"],
    [2, "CAPS"],
    [16, "MOD2"],
    [32, "MOD3"],
    [128, "MOD5"]
];

function _hyprMods(modmask) {
    var mask = Number(modmask) || 0;
    var out = [];
    _HYPR_MODS.forEach(function (entry) {
        if (mask & entry[0])
            out.push(entry[1]);
    });
    return out;
}

function _bindFromFields(fields) {
    var mods = _hyprMods(fields.modmask);
    // An empty `key` means the bind was written against a raw keycode
    // (hyprland's own `code:XX` spelling), which is what it reports back.
    var key = String(fields.key || "");
    if (key === "")
        key = "code:" + String(fields.keycode === undefined ? "" : fields.keycode);
    var arg = String(fields.arg === undefined ? "" : fields.arg);
    return {
        chord: mods.concat([key]).join("+"),
        mods: mods,
        key: key,
        action: String(fields.dispatcher || ""),
        args: arg === "" ? [] : [arg],
        title: String(fields.description || ""),
        props: {
            submap: String(fields.submap || ""),
            catchall: String(fields.catchall === "true")
        }
    };
}

// `hyprctl binds`, the plain-text table. Deliberately NOT `-j`: Hyprland
// 0.56.0's JSON encoder puts every value from `modmask` on under the
// PREVIOUS key's name and emits `allow_input_capture` with no value at all,
// so the reply is not JSON and JSON.parse throws on it, which cost the route
// every row it had. The text table carries the same binds correctly.
//
// One block per bind, headed by a bare `bind` (or `bindd`, a bind carrying a
// description) line, then one tab-indented `name: value` field per line,
// blocks separated by a blank line. A value may be empty and may itself hold
// a colon, so only the first one splits.
function parseHyprlandBinds(text) {
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    var out = [];
    var fields = null;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\s+$/, "");
        if (line === "bind" || line === "bindd") {
            if (fields)
                out.push(_bindFromFields(fields));
            fields = {};
            continue;
        }
        if (fields === null)
            continue;
        var m = /^[ \t]+([A-Za-z_][A-Za-z0-9_]*): ?(.*)$/.exec(line);
        if (m)
            fields[m[1]] = m[2];
        else if (line === "") {
            out.push(_bindFromFields(fields));
            fields = null;
        }
    }
    if (fields)
        out.push(_bindFromFields(fields));
    return out;
}

function describeAction(bind) {
    if (!bind)
        return "";
    var parts = [String(bind.action || "")];
    (bind.args || []).forEach(function (arg) {
        parts.push(String(arg));
    });
    return parts.join(" ").trim();
}

// ":k" root trigger, the same shape providers.js's ":e"/":nix" triggers
// use: the query after it, "" for the bare trigger, null when `text` is not
// the trigger at all.
function triggerQuery(text) {
    var t = String(text === undefined || text === null ? "" : text);
    if (t === ":k")
        return "";
    if (t.indexOf(":k ") === 0)
        return t.slice(3);
    return null;
}

// Chords and action names are "+"/"-"/"_"-joined, so a bare contains test
// would rank "space" against togglespecialworkspace no higher than an
// accidental substring hit.
var _WORD_BREAK = " +-_./";

function _wordStart(hay, q) {
    var at = hay.indexOf(q);
    if (at === 0)
        return true;
    while (at > 0) {
        if (_WORD_BREAK.indexOf(hay.charAt(at - 1)) >= 0)
            return true;
        at = hay.indexOf(q, at + 1);
    }
    return false;
}

// Route-local search over chord, action and arguments: exact chord >
// chord/action prefix > word start > contains, ties broken by config
// declaration order. Deliberately never reaches Search.rank, which walks
// the whole tree: a hundred-odd keybind rows there would drown every root
// search, the same reason the emoji route is special-cased.
function search(binds, query) {
    var list = binds || [];
    var q = String(query === undefined || query === null ? "" : query).trim().toLowerCase();
    if (q === "")
        return list.slice(0, KEYBINDS_MAX_RESULTS);
    var results = [];
    for (var i = 0; i < list.length; i++) {
        var bind = list[i];
        var chord = String(bind.chord || "").toLowerCase();
        var action = describeAction(bind).toLowerCase();
        var hay = chord + " " + action + " " + String(bind.title || "").toLowerCase();
        var tier;
        if (chord === q)
            tier = 4;
        else if (chord.indexOf(q) === 0 || action.indexOf(q) === 0)
            tier = 3;
        else if (_wordStart(hay, q))
            tier = 2;
        else if (hay.indexOf(q) >= 0)
            tier = 1;
        else
            continue;
        results.push({ bind: bind, tier: tier, index: i });
    }
    results.sort(function (a, b) {
        if (b.tier !== a.tier)
            return b.tier - a.tier;
        return a.index - b.index;
    });
    return results.slice(0, KEYBINDS_MAX_RESULTS).map(function (r) {
        return r.bind;
    });
}

// Rows are "note" kind, which Menu.qml's activation has no branch for, so
// they are inert by construction. That is the point: a bind acts on
// whatever window has focus, and at Enter that is the menu, so running one
// from here would fire it at whichever window the compositor hands focus
// back to instead of the one the user was looking at.
//
// No `dim` on a content row: MenuRow keys the label's ink off it, and
// `dim: true` belongs to the honest-unavailable rows below, not to a real
// keybind. The chord rides `label` at content ink, the action rides `desc`
// dimmed behind it.
//
// The id carries the row index because duplicate chords are legal (two
// submaps, a config declaring one twice) and the menu keys its node map by
// id.
function rows(binds, query) {
    var matched = search(binds, query);
    var width = 0;
    matched.forEach(function (bind) {
        var n = String(bind.chord || "").length;
        if (n > width)
            width = n;
    });
    if (width > KEYBINDS_CHORD_PAD_MAX)
        width = KEYBINDS_CHORD_PAD_MAX;
    return matched.map(function (bind, i) {
        var chord = String(bind.chord || "");
        return {
            id: "keybinds." + i + "." + chord,
            parentId: null,
            label: chord + (width > chord.length ? _PAD_CHAR.repeat(width - chord.length) : ""),
            icon: "",
            title: "",
            desc: describeAction(bind),
            aliases: [],
            kind: "note",
            childIds: []
        };
    });
}

// The three end states that are not a bind list. Each says what would fix
// it, the same shape clipsshRows' NO ALIASES row uses.
function _noteRow(id, label, desc) {
    return {
        id: id,
        parentId: null,
        label: label,
        icon: "",
        title: "",
        desc: desc,
        aliases: [],
        kind: "note",
        dim: true,
        childIds: []
    };
}

function noBindsRow() {
    return _noteRow("keybinds.nobinds", "NO BINDS", "no bind lines in the hyprland config");
}

function failedRow() {
    return _noteRow("keybinds.failed", "BINDS UNAVAILABLE", "hyprctl binds failed");
}
