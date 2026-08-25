.pragma library
.import "icons/lucide.js" as Lucide
.import "icons/nerd.js" as Nerd

// D2 (2026-08-25 shadcn redesign): icons are looked up by name, with the
// set chosen at `theme.icons` in settings.json. A name missing from a set
// falls back to that set's own "circle-help"; an unknown set name falls
// back to "lucide" entirely.

var SETS = {
    "lucide": Lucide,
    "nerd": Nerd
};

function _set(set) {
    return SETS[set] || SETS["lucide"];
}

function glyph(set, name) {
    var table = _set(set);
    return table.ICONS[name] || table.ICONS["circle-help"];
}

function family(set) {
    return _set(set).FAMILY;
}
