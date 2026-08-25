.pragma library

// Keyboard layout, normalized for the bar cell. Pure, so it's testable
// head-on (tests/tst_keyboard_layout.qml) without a compositor.
//
// The widget owns the polling: it runs `hyprctl devices -j` in its own
// Process and feeds the raw stdout to the parser here. The backend file is
// not touched.
//
// Normalized shape, produced by the parser and by unavailable():
//   { available: bool, names: [string], currentIdx: int, current: string }
// `available` false means the compositor could not be asked at all (the
// query has not answered, or it failed). The widget then renders NO LAYOUT
// rather than guessing. `currentIdx` is -1 whenever the position of the
// active layout inside `names` is not known; 0 would be a valid index and
// indistinguishable from "the first layout is active".
//
// UNVERIFIED and marked as such rather than pretended: hyprland is not a
// flake input here and no source was read, so the
// `keyboards[].{main,layout,active_keymap}` field names come from the
// Hyprland wiki. Reading src/devices/IKeyboard.cpp out of
// `nix build nixpkgs#hyprland.src` would settle it. Until then a wrong guess
// falls into unavailable() and the widget shows NO LAYOUT, which is the
// honest outcome. Hyprland also reports the two halves in different
// vocabularies (`layout` is a comma-separated list of xkb codes, "us,de",
// while `active_keymap` is a human name, "English (US)"), so there is no
// reliable index mapping between them and currentIdx stays -1.

// The shared honest-empty value: the widget's initial state and every parse
// failure land on the same object, so no call site invents its own.
function unavailable() {
    return { available: false, names: [], currentIdx: -1, current: "" };
}

// Empty for an out-of-range index, never names[0] as a guess.
function currentLayout(names, idx) {
    if (!Array.isArray(names) || names.length === 0)
        return "";
    var i = Number(idx);
    if (!isFinite(i) || i < 0 || i >= names.length)
        return "";
    return String(names[i]);
}

// The bar cell's text: the parenthetical region code, uppercased
// ("English (US)" -> "US", "English (US, intl.)" -> "US"), falling back to
// the first two letters for a name with no parenthetical ("German" -> "GE",
// and an xkb code "de" -> "DE"). The parenthetical is never truncated:
// "English (Dvorak)" reads DVORAK, because "DV" would be ambiguous.
function shortLabel(name) {
    var text = String(name || "").trim();
    if (text === "")
        return "";
    var open = text.indexOf("(");
    if (open !== -1) {
        var close = text.indexOf(")", open + 1);
        var inner = (close === -1) ? text.slice(open + 1) : text.slice(open + 1, close);
        var first = inner.split(",")[0].trim();
        if (first !== "")
            return first.toUpperCase();
    }
    return text.slice(0, 2).toUpperCase();
}

// stdout of `hyprctl devices -j`, verbatim. Reads the keyboard flagged
// `main`, falling back to the first one listed. Hyprland applies layout
// switches to the main keyboard, and a session with no keyboard at all has
// no layout to report, which is unavailable() rather than a fabricated one.
function parseHyprlandLayouts(text) {
    var raw = String(text || "").trim();
    if (raw === "")
        return unavailable();

    var data;
    try {
        data = JSON.parse(raw);
    } catch (e) {
        return unavailable();
    }
    if (!data || typeof data !== "object" || !Array.isArray(data.keyboards) || data.keyboards.length === 0)
        return unavailable();

    var main = null;
    for (var i = 0; i < data.keyboards.length; i++) {
        if (data.keyboards[i] && data.keyboards[i].main === true) {
            main = data.keyboards[i];
            break;
        }
    }
    if (main === null)
        main = data.keyboards[0] || {};

    var names = String(main.layout || "").split(",").map(function (s) {
        return s.trim();
    }).filter(function (s) {
        return s !== "";
    });
    var current = String(main.active_keymap || "");
    if (names.length === 0 && current === "")
        return unavailable();

    return { available: true, names: names, currentIdx: -1, current: current };
}

// The bar cell's `shown` gate. A single-layout session has nothing to
// report and a permanently static cell is noise, the same judgement
// Battery.qml makes with no battery.
function hasChoice(layout) {
    var l = layout || {};
    return l.available === true && Array.isArray(l.names) && l.names.length >= 2;
}

// One tooltip string, active layout first, joined " / " per DESIGN.md §2
// item 10. Uppercased to sit in the meta band with every other tooltip.
function tooltipText(layout) {
    var l = layout || {};
    if (l.available !== true)
        return "NO LAYOUT";

    var names = Array.isArray(l.names) ? l.names.slice() : [];
    var idx = Number(l.currentIdx);
    var current = String(l.current || "");
    if (isFinite(idx) && idx >= 0 && idx < names.length) {
        var head = names.splice(idx, 1);
        names = head.concat(names);
    } else if (current !== "") {
        names = [current].concat(names);
    }
    if (names.length === 0)
        return "NO LAYOUT";

    return names.map(function (n) { return String(n).toUpperCase(); }).join(" / ");
}
