.pragma library

// What a key is called on its cap (Keycap.qml, Chord.qml). One spelling per
// key whatever produced the string: Hyprland's own `SUPER`, a table's
// `Super`, a legend's `Escape`. Arrows are icons rather than glyphs, since
// the arrow codepoints are not in every face `monospace` resolves to.

var NAMES = {
    "super": "Super",
    "mod4": "Super",
    "alt": "Alt",
    "mod1": "Alt",
    "ctrl": "Ctrl",
    "control": "Ctrl",
    "shift": "Shift",
    "enter": "Enter",
    "return": "Enter",
    "escape": "Esc",
    "esc": "Esc",
    "tab": "Tab",
    "space": "Space",
    "backspace": "Backspace",
    "delete": "Del",
    "del": "Del",
    "pageup": "PgUp",
    "pagedown": "PgDn",
    "home": "Home",
    "end": "End"
};

var ICONS = {
    "up": "arrow-up",
    "down": "arrow-down",
    "left": "arrow-left",
    "right": "arrow-right"
};

// `{ text, icon }` for one key: exactly one of the two is non-empty. A key
// no table knows keeps its own spelling, a single letter uppercased the way
// it is printed on the key.
function cap(key) {
    var raw = String(key === undefined || key === null ? "" : key).trim();
    var low = raw.toLowerCase();
    if (ICONS[low] !== undefined)
        return { text: "", icon: ICONS[low] };
    if (NAMES[low] !== undefined)
        return { text: NAMES[low], icon: "" };
    if (raw.length === 1)
        return { text: raw.toUpperCase(), icon: "" };
    return { text: raw, icon: "" };
}

// A chord string (`Super+Alt+Space`) or an array of keys, as the list of
// keys it presses, one per cap. A `+` that is itself the key survives: the
// empty field a split leaves beside it is what marks it.
function split(chord) {
    if (chord === undefined || chord === null)
        return [];
    // A list reaches here from a model as a sequence rather than a JS
    // array, so `length` is the test, not `Array.isArray`.
    if (typeof chord === "object" && chord.length !== undefined) {
        var keys = [];
        for (var k = 0; k < chord.length; k++) {
            var key = String(chord[k]).trim();
            if (key !== "")
                keys.push(key);
        }
        return keys;
    }
    var s = String(chord).trim();
    if (s === "")
        return [];
    if (s === "+")
        return ["+"];
    var parts = s.split("+");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i].trim();
        if (part !== "")
            out.push(part);
        else if (i === parts.length - 1 && i > 0)
            out.push("+");
    }
    return out;
}

