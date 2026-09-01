.pragma library

// Zenbones (github.com/zenbones-theme/zenbones.nvim) as data, in the same
// three views flexoki.js carries: theme.json's shadcn roles, the Material
// roles every matugen template is written against, and the base16 slots a
// terminal palette is built from. palette.js registers it as a pinned
// palette, so a wallpaper whose path carries "zenbones" lands on these tones
// instead of a scheme grown from its pixels.
//
// Zenbones has no published ramps: the upstream palette is eight hsluv seeds
// per mode plus lush derivations (lua/zenbones/palette.lua,
// specs/{dark,light}.lua). Every hex here was computed from those exact
// derivations with lush's own arithmetic (h/s/l round to integers between
// ops), and the computation was verified against the repo's generated kitty
// port (extras/kitty/zenbones_{dark,light}.conf): all 32 port values and
// both Visual selections reproduce byte for byte. Tones with no upstream
// name reuse the spec's own idioms (the surface ladder is CursorLine/
// NormalFloat/Folded/PmenuSel, containers are the DiffAdd recipe) rather
// than inventing new colours; each carries its derivation.
//
// Hue mapping is zenbones' own terminal port (lua/zenbones/term.lua):
// red=rose, green=leaf, yellow=wood, blue=water, magenta=blossom, cyan=sky.
// The scheme has six chromatics, so orange doubles on wood and purple on
// blossom. Bright ANSI is the same mode's `1` variants, not the other
// mode's stops (unlike Flexoki, whose ports spend both mode stops).

var TONES = {
    dark: {
        bg: "#1c1917",        // hsluv(39,12,9)
        surface1: "#25211f",  // bg.li(4)   CursorLine
        surface2: "#302b29",  // bg.li(10)  NormalFloat/Pmenu
        surface3: "#393431",  // bg.li(14)  Folded
        surface4: "#4a433f",  // bg.li(22)  PmenuSel
        bg1: "#403833",       // bg.sa(4).li(16)  bright black
        sel: "#3d4042",       // fg.de(18).lightness(bg.l+18)  Visual
        linenr: "#685f5a",    // bg.li(35)  LineNr
        comment: "#6e6763",   // bg.li(38).de(24)  Comment
        fgdim: "#888f94",     // fg.da(22)  terminal bright white
        fg: "#b4bdc3",        // hsluv(230,10,76)
        fgbright: "#c4cacf",  // fg.li(20)  Cursor
        fgbrighter: "#d3d8db", // fg.li(40)
        rose: "#de6e7c", leaf: "#819b69", wood: "#b77e64",
        water: "#6099c0", blossom: "#b279a7", sky: "#66a5ad",
        rose1: "#e8838f", leaf1: "#8bae68", wood1: "#d68c67",
        water1: "#61abda", blossom1: "#cf86c1", sky1: "#65b8c1",
        // DiffAdd recipe: hue.saturation(n).lightness(bg.l+8); n is the
        // spec's own per-hue saturation (water/sky 50, wood 46, rose 30).
        waterC: "#1d2c36", skyC: "#1c2d2f", woodC: "#39251c", roseC: "#3e2225"
    },
    light: {
        bg: "#f0edec",        // hsluv(39,12,94)
        surface1: "#e9e4e2",  // bg.da(3)   CursorLine
        surface2: "#ddd6d3",  // bg.da(8)   NormalFloat
        surface3: "#dad3cf",  // bg.da(10)  Pmenu
        surface4: "#c4b6af",  // bg.da(20)  PmenuSel
        bg1: "#cfc1ba",       // bg.sa(4).da(16)  bright black
        sel: "#cbd9e3",       // fg.lightness(bg.l-8)  Visual
        linenr: "#a4968f",    // bg.da(33)  LineNr
        comment: "#948985",   // bg.da(38).de(28)  Comment
        fgdim: "#4f5e68",     // fg.li(22)  terminal bright white
        fg: "#2c363c",        // hsluv(230,30,22)
        fg1s: "#3e4b53",      // fg.li(11)  spec fg1
        fg2s: "#44525b",      // fg.li(15)  spec fg2
        rose: "#a8334c", leaf: "#4f6c31", wood: "#944927",
        water: "#286486", blossom: "#88507d", sky: "#3b8992",
        rose1: "#94253e", leaf1: "#3f5a22", wood1: "#803d1c",
        water1: "#1d5573", blossom1: "#7b3b70", sky1: "#2b747c",
        // DiffAdd recipe, lightness bg.l-6 (water/sky 30, wood 46, rose 40).
        waterC: "#d4dee7", skyC: "#c3e2e7", woodC: "#edd8d4", roseC: "#ebd8da"
    }
};

// Material's `*_fixed` family is mode-independent by definition, so it is
// derived once from the light-mode hue seeds: fixed is
// saturation(30).lightness(85), on_fixed lightness(15), on_fixed_variant
// lightness(35); fixed_dim is the dark-mode stop (Material's own shape:
// a dim accent that works on the fixed pastel).
var FIXED = {
    water: { fixed: "#cad6e2", dim: "#6099c0", on: "#0c2838", onVariant: "#225775" },
    sky: { fixed: "#b6dbe0", dim: "#66a5ad", on: "#0d2a2d", onVariant: "#245a60" },
    wood: { fixed: "#e3d1cd", dim: "#b77e64", on: "#3f1c0b", onVariant: "#824021" }
};

// What a pinned run hands `matugen color hex` in place of the image: water
// (the blue), zenbones' de-facto accent. Only seeds the roles no rewrite
// covers, same as Flexoki's SOURCE.
var SOURCE = TONES.dark.water;

function _t(mode) {
    return mode === "light" ? TONES.light : TONES.dark;
}

// theme.json's shadcn roles. The surface ladder fills the neutral slots,
// water is `primary` and `ring`, rose destructive, wood warning, and
// chart1..5 walk the chromatics.
function shadcn(mode) {
    var t = _t(mode);
    var onAccent = t.bg;
    return {
        mode: mode === "light" ? "light" : "dark",
        background: t.bg, foreground: t.fg,
        card: t.surface1, cardForeground: t.fg,
        popover: t.surface2, popoverForeground: t.fg,
        primary: t.water, primaryForeground: onAccent,
        secondary: t.surface2, secondaryForeground: t.fg,
        muted: t.surface2, mutedForeground: t.fgdim,
        accent: mode === "light" ? t.surface3 : t.surface4, accentForeground: t.fg,
        destructive: t.rose, destructiveForeground: onAccent,
        warning: t.wood, warningForeground: onAccent,
        border: t.bg1, input: t.bg1, ring: t.water,
        chart1: t.water, chart2: t.sky, chart3: t.wood,
        chart4: t.leaf, chart5: t.blossom
    };
}

// base16 over the same tones: the gray ramp walks bg → surface2 → Visual →
// Comment → dim fg → fg → the spec's own brighter/darker fg steps, accents
// sit in the canonical slots (0F takes wood, the scheme's brown).
function base16(mode) {
    var t = _t(mode);
    return {
        base00: t.bg,
        base01: t.surface2,
        base02: t.sel,
        base03: t.comment,
        base04: t.fgdim,
        base05: t.fg,
        base06: mode === "light" ? t.fg1s : t.fgbright,
        base07: mode === "light" ? t.fg2s : t.fgbrighter,
        base08: t.rose,
        base09: t.wood,
        base0A: t.wood,
        base0B: t.leaf,
        base0C: t.sky,
        base0D: t.water,
        base0E: t.blossom,
        base0F: t.wood
    };
}

// Every role matugen emits under `colors.*`, each carrying a zenbones tone.
// The accents follow the shadcn view above: water primary, sky secondary,
// wood tertiary (the warning colour), rose error. outline is the LineNr
// tone and outline_variant the bright black, so hairlines stay subtler than
// dividers in both modes; ANSI 8 (a template reads it off outline) lands on
// LineNr gray rather than the port's bright black, the one deliberate
// deviation from the kitty port.
//
// The eight hue names and their `_alt` twins ride along for terminal
// templates, exactly like flexoki.js; `_alt` is the mode's own bright
// variant, which is what zenbones' ports spend on ANSI 9-14.
function materialRoles(mode) {
    var dark = mode !== "light";
    var t = _t(mode);
    var other = _t(dark ? "light" : "dark");

    var roles = {
        source_color: SOURCE,
        surface_tint: t.water,

        primary: t.water,
        on_primary: t.bg,
        primary_container: t.waterC,
        on_primary_container: t.water1,
        inverse_primary: other.water,
        primary_fixed: FIXED.water.fixed,
        primary_fixed_dim: FIXED.water.dim,
        on_primary_fixed: FIXED.water.on,
        on_primary_fixed_variant: FIXED.water.onVariant,

        secondary: t.sky,
        on_secondary: t.bg,
        secondary_container: t.skyC,
        on_secondary_container: t.sky1,
        secondary_fixed: FIXED.sky.fixed,
        secondary_fixed_dim: FIXED.sky.dim,
        on_secondary_fixed: FIXED.sky.on,
        on_secondary_fixed_variant: FIXED.sky.onVariant,

        tertiary: t.wood,
        on_tertiary: t.bg,
        tertiary_container: t.woodC,
        on_tertiary_container: t.wood1,
        tertiary_fixed: FIXED.wood.fixed,
        tertiary_fixed_dim: FIXED.wood.dim,
        on_tertiary_fixed: FIXED.wood.on,
        on_tertiary_fixed_variant: FIXED.wood.onVariant,

        error: t.rose,
        on_error: t.bg,
        error_container: t.roseC,
        on_error_container: t.rose1,

        background: t.bg,
        on_background: t.fg,
        surface: t.bg,
        on_surface: t.fg,
        surface_dim: dark ? t.bg : t.surface3,
        surface_bright: dark ? t.surface4 : t.bg,
        surface_container_lowest: t.bg,
        surface_container_low: t.surface1,
        surface_container: t.surface2,
        surface_container_high: t.surface3,
        surface_container_highest: t.surface4,
        surface_variant: t.surface2,
        on_surface_variant: t.fgdim,
        inverse_surface: t.fg,
        inverse_on_surface: t.bg,

        outline: t.linenr,
        outline_variant: t.bg1,
        scrim: TONES.dark.bg,
        shadow: TONES.dark.bg
    };

    var hueMap = {
        red: "rose", orange: "wood", yellow: "wood", green: "leaf",
        cyan: "sky", blue: "water", purple: "blossom", magenta: "blossom"
    };
    for (var name in hueMap) {
        roles[name] = t[hueMap[name]];
        roles[name + "_alt"] = t[hueMap[name] + "1"];
    }
    return roles;
}
