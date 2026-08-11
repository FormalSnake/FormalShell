.pragma library

// Compositor keybinds -> menu rows. Pure, so the KDL scanner is testable
// head-on (tests/tst_keybinds.qml); the config read and the hyprctl process
// stay in the menu surface.
//
// The niri leg scans config.kdl text, so it has to survive real configs:
// quoted strings holding braces or "//", line and block comments, "/-"
// slashdash node comments, KDL v2 raw and multi-line strings, node
// properties, and a binds block that is not the first block in the file. A
// line splitter or a whole-file regex breaks on every one of those. The
// hyprland leg maps `hyprctl binds -j`, which is real JSON.
//
// Nothing here throws. A half-written config yields the binds above the
// mistake instead of an empty surface, which is the honest answer for a
// file the user is editing right now.
//
// A Bind is:
//   { chord: "Mod+Shift+Slash", mods: ["Mod", "Shift"], key: "Slash",
//     action: "show-hotkey-overlay", args: [], title: "",
//     props: { "repeat": "false" } }

var KEYBINDS_CHORD_PAD_MAX = 24;
var KEYBINDS_MAX_RESULTS = 200;

// Chords are padded into a column with U+00A0, not ASCII space: a Text
// item's implicit width drops trailing ASCII whitespace, so a space-padded
// label would measure as the bare chord and the column would collapse.
var _PAD_CHAR = "\u00a0";

var _ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "b": "\b",
    "f": "\f",
    "s": " ",
    "\\": "\\",
    "\"": "\"",
    "/": "/"
};

function _unescape(text, i) {
    var c = text.charAt(i + 1);
    if (c === "u" && text.charAt(i + 2) === "{") {
        var close = text.indexOf("}", i + 3);
        if (close > i + 3) {
            var code = parseInt(text.slice(i + 3, close), 16);
            if (isFinite(code) && code >= 0 && code <= 0x10FFFF)
                return { value: String.fromCodePoint(code), next: close + 1 };
        }
    }
    if (_ESCAPES[c] !== undefined)
        return { value: _ESCAPES[c], next: i + 2 };
    return { value: c, next: i + 2 };
}

// The KDL string starting at `i`, or null when none does. Covers plain
// "...", KDL v2 raw strings (#"..."#, any hash count, no escapes) and
// triple-quoted multi-line strings. An unterminated string ends at end of
// text rather than spinning. The dedent KDL v2 applies to a multi-line
// string's closing line is not reproduced: the value only ever reaches a
// row description.
function _readString(text, i) {
    var len = text.length;
    var hashes = 0;
    var j = i;
    while (j < len && text.charAt(j) === "#") {
        hashes++;
        j++;
    }
    if (j >= len || text.charAt(j) !== "\"")
        return null;
    var multi = text.substr(j, 3) === "\"\"\"";
    var close = (multi ? "\"\"\"" : "\"") + (hashes > 0 ? "#".repeat(hashes) : "");
    var raw = hashes > 0;
    var k = j + (multi ? 3 : 1);
    var value = "";
    while (k < len) {
        if (!raw && text.charAt(k) === "\\" && k + 1 < len) {
            var esc = _unescape(text, k);
            value += esc.value;
            k = esc.next;
            continue;
        }
        if (text.substr(k, close.length) === close) {
            if (multi && value.charAt(0) === "\n")
                value = value.slice(1);
            return { value: value, next: k + close.length, quoted: true };
        }
        value += text.charAt(k);
        k++;
    }
    return { value: value, next: len, quoted: true };
}

var _WORD_STOP = " \t\r\n{};=\"/\\";

function _readWord(text, i) {
    var len = text.length;
    var j = i;
    while (j < len && _WORD_STOP.indexOf(text.charAt(j)) < 0)
        j++;
    if (j === i)
        return null;
    return { value: text.slice(i, j), next: j, quoted: false };
}

function _readTerm(text, i) {
    return _readString(text, i) || _readWord(text, i);
}

// Whitespace and comments between tokens. `stopAtNewline` keeps a newline
// as the node terminator it is; an escaped newline (KDL's escline) is
// trivia either way. Block comments nest.
function _skipTrivia(text, i, stopAtNewline) {
    var len = text.length;
    while (i < len) {
        var c = text.charAt(i);
        if (c === " " || c === "\t" || c === "\r") {
            i++;
            continue;
        }
        if (c === "\n") {
            if (stopAtNewline)
                return i;
            i++;
            continue;
        }
        if (c === "\\") {
            var j = i + 1;
            while (j < len && (text.charAt(j) === " " || text.charAt(j) === "\t" || text.charAt(j) === "\r"))
                j++;
            if (text.charAt(j) !== "\n")
                return i;
            i = j + 1;
            continue;
        }
        if (c === "/" && text.charAt(i + 1) === "/") {
            while (i < len && text.charAt(i) !== "\n")
                i++;
            continue;
        }
        if (c === "/" && text.charAt(i + 1) === "*") {
            var depth = 1;
            i += 2;
            while (i < len && depth > 0) {
                if (text.charAt(i) === "/" && text.charAt(i + 1) === "*") {
                    depth++;
                    i += 2;
                    continue;
                }
                if (text.charAt(i) === "*" && text.charAt(i + 1) === "/") {
                    depth--;
                    i += 2;
                    continue;
                }
                i++;
            }
            continue;
        }
        return i;
    }
    return i;
}

// Index of the "}" closing the block whose body starts at `i`, or end of
// text when the file stops first.
function _matchBrace(text, i) {
    var len = text.length;
    var depth = 1;
    while (i < len) {
        var t = _skipTrivia(text, i, false);
        if (t !== i) {
            i = t;
            continue;
        }
        var str = _readString(text, i);
        if (str) {
            i = str.next;
            continue;
        }
        var c = text.charAt(i);
        if (c === "{")
            depth++;
        else if (c === "}") {
            depth--;
            if (depth === 0)
                return i;
        }
        i++;
    }
    return len;
}

// [start, end) of the binds block's body. Braces are counted only outside
// strings and comments, which is what lets a preceding sibling block
// (layout { border { ... } }) be walked past instead of latched onto. A
// "/-"-commented binds block is skipped like any other disabled node.
function _findBindsBody(text) {
    var len = text.length;
    var i = 0;
    var depth = 0;
    var slashdash = false;
    while (i < len) {
        var t = _skipTrivia(text, i, false);
        if (t !== i) {
            i = t;
            continue;
        }
        var str = _readString(text, i);
        if (str) {
            i = str.next;
            slashdash = false;
            continue;
        }
        var c = text.charAt(i);
        if (c === "/" && text.charAt(i + 1) === "-") {
            slashdash = true;
            i += 2;
            continue;
        }
        if (c === "{") {
            depth++;
            i++;
            continue;
        }
        if (c === "}") {
            if (depth > 0)
                depth--;
            i++;
            continue;
        }
        var word = _readWord(text, i);
        if (!word) {
            i++;
            continue;
        }
        i = word.next;
        var disabled = slashdash;
        slashdash = false;
        if (depth !== 0 || word.value !== "binds")
            continue;
        var after = _skipTrivia(text, i, false);
        if (text.charAt(after) !== "{")
            continue;
        var end = _matchBrace(text, after + 1);
        if (!disabled)
            return { start: after + 1, end: end };
        i = end + 1;
    }
    return null;
}

// Where the node starting at `i` ends: at the first ";" or newline at depth
// zero, or right after its own children block closes.
function _nodeSpan(body, i) {
    var len = body.length;
    var start = i;
    var depth = 0;
    while (i < len) {
        var t = _skipTrivia(body, i, true);
        if (t !== i) {
            i = t;
            continue;
        }
        var str = _readString(body, i);
        if (str) {
            i = str.next;
            continue;
        }
        var c = body.charAt(i);
        if (c === "{") {
            depth++;
            i++;
            continue;
        }
        if (c === "}") {
            if (depth === 0)
                return { start: start, end: i, next: i };
            depth--;
            i++;
            if (depth === 0)
                return { start: start, end: i, next: i };
            continue;
        }
        if (depth === 0 && (c === ";" || c === "\n"))
            return { start: start, end: i, next: i + 1 };
        i++;
    }
    return { start: start, end: len, next: len };
}

// Node sources inside a block body, in declaration order. A "/-" prefix
// drops the node that follows it, so a disabled bind never shows up as a
// live one.
function _splitNodes(body) {
    var len = body.length;
    var out = [];
    var i = 0;
    while (i < len) {
        i = _skipTrivia(body, i, false);
        if (i >= len)
            break;
        var c = body.charAt(i);
        if (c === ";" || c === "}") {
            i++;
            continue;
        }
        var dropped = false;
        if (c === "/" && body.charAt(i + 1) === "-") {
            dropped = true;
            i = _skipTrivia(body, i + 2, false);
        }
        var span = _nodeSpan(body, i);
        if (!dropped && span.end > span.start)
            out.push(body.slice(span.start, span.end));
        i = span.next > i ? span.next : i + 1;
    }
    return out;
}

// KDL v2 spells keywords "#true"/"#false"/"#null" where v1 spells them
// bare. Values stay source text either way, never coerced to a bool or a
// number: an id or an index that reads as a number is still an opaque
// string here.
function _propValue(term) {
    if (term.quoted)
        return term.value;
    return term.value.charAt(0) === "#" ? term.value.slice(1) : term.value;
}

// The block's first child node names the action and carries its arguments.
// Later children are ignored rather than merged: an unknown extra child is
// a niri version this parser predates, not something to guess at.
function _parseActionNode(src) {
    var len = src.length;
    var i = _skipTrivia(src, 0, false);
    var name = _readTerm(src, i);
    if (!name)
        return { action: "", args: [] };
    i = name.next;
    var args = [];
    while (i < len) {
        i = _skipTrivia(src, i, false);
        if (i >= len || src.charAt(i) === "{")
            break;
        var term = _readTerm(src, i);
        if (!term) {
            i++;
            continue;
        }
        i = term.next;
        if (src.charAt(i) === "=") {
            var val = _readTerm(src, i + 1);
            i = val ? val.next : i + 1;
            continue;
        }
        args.push(term.value);
    }
    return { action: name.value, args: args };
}

function _parseBindNode(src) {
    var len = src.length;
    var i = _skipTrivia(src, 0, false);
    var head = _readTerm(src, i);
    if (!head || head.value === "")
        return null;
    i = head.next;
    var props = {};
    var title = "";
    while (i < len) {
        i = _skipTrivia(src, i, false);
        if (i >= len || src.charAt(i) === "{")
            break;
        var term = _readTerm(src, i);
        if (!term) {
            i++;
            continue;
        }
        i = term.next;
        if (src.charAt(i) !== "=")
            continue;
        var val = _readTerm(src, i + 1);
        if (!val) {
            i++;
            continue;
        }
        i = val.next;
        props[term.value] = _propValue(val);
        if (term.value === "hotkey-overlay-title" && val.quoted)
            title = val.value;
    }
    var action = "";
    var args = [];
    if (i < len && src.charAt(i) === "{") {
        var children = _splitNodes(src.slice(i + 1, _matchBrace(src, i + 1)));
        if (children.length > 0) {
            var parsed = _parseActionNode(children[0]);
            action = parsed.action;
            args = parsed.args;
        }
    }
    // niri spells the plus key "Plus", so splitting the chord on "+" can
    // only ever separate modifiers from the key.
    var parts = head.value.split("+");
    return {
        chord: head.value,
        mods: parts.slice(0, parts.length - 1),
        key: parts[parts.length - 1],
        action: action,
        args: args,
        title: title,
        props: props
    };
}

function parseNiriBinds(text) {
    var src = String(text === undefined || text === null ? "" : text);
    if (src === "")
        return [];
    var block = _findBindsBody(src);
    if (!block)
        return [];
    var out = [];
    _splitNodes(src.slice(block.start, block.end)).forEach(function (nodeSrc) {
        var bind = _parseBindNode(nodeSrc);
        if (bind)
            out.push(bind);
    });
    return out;
}

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

// `hyprctl binds -j`. Strictly better input than the niri leg's KDL:
// hyprland has already expanded its own sources and submaps, so there is
// no include chain and no scanner to get wrong.
function parseHyprlandBinds(text) {
    var list;
    try {
        list = JSON.parse(String(text === undefined || text === null ? "" : text));
    } catch (e) {
        return [];
    }
    if (!Array.isArray(list))
        return [];
    return list.map(function (entry) {
        entry = entry || {};
        var mods = _hyprMods(entry.modmask);
        // An empty `key` means the bind was written against a raw keycode
        // (hyprland's own `code:XX` spelling), which is what it reports back.
        var key = String(entry.key || "");
        if (key === "")
            key = "code:" + String(entry.keycode === undefined ? "" : entry.keycode);
        var arg = String(entry.arg === undefined || entry.arg === null ? "" : entry.arg);
        return {
            chord: mods.concat([key]).join("+"),
            mods: mods,
            key: key,
            action: String(entry.dispatcher || ""),
            args: arg === "" ? [] : [arg],
            title: String(entry.description || ""),
            props: {
                submap: String(entry.submap || ""),
                locked: String(entry.locked === true),
                release: String(entry.release === true),
                repeat: String(entry.repeat === true)
            }
        };
    });
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
// would rank "column" against move-column-to-workspace no higher than an
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
// hyprland submaps, a config declaring one twice) and the menu keys its
// node map by id.
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

// The four end states that are not a bind list. Each says what would fix
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

function noConfigRow() {
    return _noteRow("keybinds.noconfig", "NO CONFIG", "~/.config/niri/config.kdl");
}

function noBindsRow() {
    return _noteRow("keybinds.nobinds", "NO BINDS", "no binds block in the config");
}

function failedRow() {
    return _noteRow("keybinds.failed", "BINDS UNAVAILABLE", "hyprctl binds -j failed");
}

function unsupportedRow() {
    return _noteRow("keybinds.unsupported", "NO BINDS", "niri or hyprland only");
}
