.pragma library

// Flexoki (stephango.com/flexoki, github.com/kepano/flexoki) as data, and the
// three views the shell renders it through: theme.json's shadcn roles, the
// Material roles every matugen template is written against, and the base16
// slots a terminal palette is built from.
//
// One table, because a Flexoki-pinned wallpaper has to reach three sinks that
// used to disagree. theme.json and the Hyprland colours files take the shadcn
// view directly; every template (the shell's GTK/Qt ones and the user's own)
// is written against matugen's role names, so a pinned run rewrites those
// names to materialRoles() values before matugen ever sees the file. Without
// that rewrite matugen renders them from a Material scheme grown out of one
// blue seed, and a terminal whose ANSI slots read primary/secondary/tertiary
// comes out monochrome blue.
//
// Ramp values are the canonical palette
// (github.com/kepano/flexoki/tree/main/tailwind), cross-checked against
// Ghostty's bundled Flexoki Light/Dark. Flexoki's own rule: the 600 stops sit
// on light backgrounds, the 400 stops on dark ones.

var BASE = {
    paper: "#fffcf0", black: "#100f0f",
    "50": "#f2f0e5", "100": "#e6e4d9", "150": "#dad8ce", "200": "#cecdc3", "300": "#b7b5ac",
    "400": "#9f9d96", "500": "#878580", "600": "#6f6e69", "700": "#575653",
    "800": "#403e3c", "850": "#343331", "900": "#282726", "950": "#1c1b1a"
};

var HUES = {
    red: {
        "50": "#ffe1d5", "100": "#ffcabb", "150": "#fdb2a2", "200": "#f89a8a", "300": "#e8705f",
        "400": "#d14d41", "500": "#c03e35", "600": "#af3029", "700": "#942822",
        "800": "#6c201c", "850": "#551b18", "900": "#3e1715", "950": "#261312"
    },
    orange: {
        "50": "#ffe7ce", "100": "#fed3af", "150": "#fcc192", "200": "#f9ae77", "300": "#ec8b49",
        "400": "#da702c", "500": "#cb6120", "600": "#bc5215", "700": "#9d4310",
        "800": "#71320d", "850": "#59290d", "900": "#40200d", "950": "#27180e"
    },
    yellow: {
        "50": "#faeec6", "100": "#f6e2a0", "150": "#f1d67e", "200": "#eccb60", "300": "#dfb431",
        "400": "#d0a215", "500": "#be9207", "600": "#ad8301", "700": "#8e6b01",
        "800": "#664d01", "850": "#503d02", "900": "#3a2d04", "950": "#241e08"
    },
    green: {
        "50": "#edeecf", "100": "#dde2b2", "150": "#cdd597", "200": "#bec97e", "300": "#a0af54",
        "400": "#879a39", "500": "#768d21", "600": "#66800b", "700": "#536907",
        "800": "#3d4c07", "850": "#313d07", "900": "#252d09", "950": "#1a1e0c"
    },
    cyan: {
        "50": "#ddf1e4", "100": "#bfe8d9", "150": "#a2dece", "200": "#87d3c3", "300": "#5abdac",
        "400": "#3aa99f", "500": "#2f968d", "600": "#24837b", "700": "#1c6c66",
        "800": "#164f4a", "850": "#143f3c", "900": "#122f2c", "950": "#101f1d"
    },
    blue: {
        "50": "#e1eceb", "100": "#c6dde8", "150": "#abcfe2", "200": "#92bfdb", "300": "#66a0c8",
        "400": "#4385be", "500": "#3171b2", "600": "#205ea6", "700": "#1a4f8c",
        "800": "#163b66", "850": "#133051", "900": "#12253b", "950": "#101a24"
    },
    purple: {
        "50": "#f0eaec", "100": "#e2d9e9", "150": "#d3cae6", "200": "#c4b9e0", "300": "#a699d0",
        "400": "#8b7ec8", "500": "#735eb5", "600": "#5e409d", "700": "#4f3685",
        "800": "#3c2a62", "850": "#31234e", "900": "#261c39", "950": "#1a1623"
    },
    magenta: {
        "50": "#fee4e5", "100": "#fccfda", "150": "#f9b9cf", "200": "#f4a4c2", "300": "#e47da8",
        "400": "#ce5d97", "500": "#b74583", "600": "#a02f6f", "700": "#87285e",
        "800": "#641f46", "850": "#4f1b39", "900": "#39172b", "950": "#24131d"
    }
};

var HUE_NAMES = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta"];

// The colour Flexoki's own site links in, and what a pinned run hands
// `matugen color hex` in place of the image. Every {{colors.*}} a template
// asks for is rewritten before matugen runs, so this now only seeds the
// roles no rewrite covers (a custom_colors entry the user declared himself).
var SOURCE = HUES.blue["400"];

function _dark(mode) {
    return mode !== "light";
}

// The mode's own accent stop, and the stop the other mode uses. Flexoki's
// terminal ports spend both: ANSI 1-6 on the mode's stop, ANSI 9-14 on the
// other one, which is why altStop() exists at all.
function stop(hue, mode) {
    return HUES[hue][_dark(mode) ? "400" : "600"];
}

function altStop(hue, mode) {
    return HUES[hue][_dark(mode) ? "600" : "400"];
}

// theme.json's shadcn roles. Base tones fill the surfaces (black/b950/b900
// dark, paper/b50/b100 light), blue is `primary` and `ring`, and chart1..5
// walk the accents since this palette has real ones to draw from.
function shadcn(mode) {
    if (!_dark(mode)) {
        return {
            mode: "light",
            background: BASE.paper, foreground: BASE.black,
            card: BASE["50"], cardForeground: BASE.black,
            popover: BASE["100"], popoverForeground: BASE.black,
            primary: HUES.blue["600"], primaryForeground: BASE.paper,
            secondary: BASE["100"], secondaryForeground: BASE.black,
            muted: BASE["100"], mutedForeground: BASE["600"],
            accent: BASE["150"], accentForeground: BASE.black,
            destructive: HUES.red["600"], destructiveForeground: BASE.paper,
            warning: HUES.orange["600"], warningForeground: BASE.paper,
            border: BASE["150"], input: BASE["150"], ring: HUES.blue["600"],
            chart1: HUES.blue["600"], chart2: HUES.cyan["600"], chart3: HUES.orange["600"],
            chart4: HUES.green["600"], chart5: HUES.purple["600"]
        };
    }
    return {
        mode: "dark",
        background: BASE.black, foreground: BASE["200"],
        card: BASE["950"], cardForeground: BASE["200"],
        popover: BASE["900"], popoverForeground: BASE["200"],
        primary: HUES.blue["400"], primaryForeground: BASE.black,
        secondary: BASE["900"], secondaryForeground: BASE["200"],
        muted: BASE["900"], mutedForeground: BASE["500"],
        accent: BASE["850"], accentForeground: BASE["200"],
        destructive: HUES.red["400"], destructiveForeground: BASE.black,
        warning: HUES.orange["400"], warningForeground: BASE.black,
        border: BASE["800"], input: BASE["800"], ring: HUES.blue["400"],
        chart1: HUES.blue["400"], chart2: HUES.cyan["400"], chart3: HUES.orange["400"],
        chart4: HUES.green["400"], chart5: HUES.purple["400"]
    };
}

// Flexoki's own base16 view (the mapping its bat/fish/tmTheme ports use).
// base06 is absent from the upstream table, so it takes the step between
// base05 and base07 rather than being invented.
function base16(mode) {
    var dark = _dark(mode);
    var out = {
        base00: dark ? BASE.black : BASE.paper,
        base01: dark ? BASE["950"] : BASE["50"],
        base02: dark ? BASE["900"] : BASE["100"],
        base03: dark ? BASE["700"] : BASE["300"],
        base04: dark ? BASE["500"] : BASE["600"],
        base05: dark ? BASE["200"] : BASE.black,
        base06: dark ? BASE["150"] : BASE["950"],
        base07: dark ? BASE["100"] : BASE["900"]
    };
    var slots = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta"];
    var names = ["base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"];
    for (var i = 0; i < slots.length; i++)
        out[names[i]] = stop(slots[i], mode);
    return out;
}

// Every role matugen emits under `colors.*` (matugen 4.1.0, `-j hex` on a
// bare config lists 50 including source_color), each carrying a real Flexoki
// tone. The accents follow the shadcn view above so a template and the shell
// never disagree: blue is primary, cyan secondary, orange tertiary (the
// warning colour), red error. Containers take the hue's 900 stop on dark and
// its 100 stop on light; the `*_fixed` family is mode-independent by
// definition, so both modes get the same pair.
//
// Eight hue names ride along past matugen's own list (red, orange, yellow,
// green, cyan, blue, purple, magenta, and a `_alt` twin each). Material has
// no green or yellow role, so a terminal template that wants a real ANSI ramp
// has nowhere else to read one from; declaring the same names under
// [config.custom_colors] in ~/.config/matugen/config.toml gets the same
// template a wallpaper-harmonised ramp on every other wallpaper.
function materialRoles(mode) {
    var dark = _dark(mode);
    var containerStep = dark ? "900" : "100";
    var onContainerStep = dark ? "150" : "800";
    var onAccent = dark ? BASE.black : BASE.paper;

    var roles = {
        source_color: SOURCE,
        surface_tint: stop("blue", mode),

        primary: stop("blue", mode),
        on_primary: onAccent,
        primary_container: HUES.blue[containerStep],
        on_primary_container: HUES.blue[onContainerStep],
        inverse_primary: altStop("blue", mode),
        primary_fixed: HUES.blue["150"],
        primary_fixed_dim: HUES.blue["400"],
        on_primary_fixed: HUES.blue["950"],
        on_primary_fixed_variant: HUES.blue["700"],

        secondary: stop("cyan", mode),
        on_secondary: onAccent,
        secondary_container: HUES.cyan[containerStep],
        on_secondary_container: HUES.cyan[onContainerStep],
        secondary_fixed: HUES.cyan["150"],
        secondary_fixed_dim: HUES.cyan["400"],
        on_secondary_fixed: HUES.cyan["950"],
        on_secondary_fixed_variant: HUES.cyan["700"],

        tertiary: stop("orange", mode),
        on_tertiary: onAccent,
        tertiary_container: HUES.orange[containerStep],
        on_tertiary_container: HUES.orange[onContainerStep],
        tertiary_fixed: HUES.orange["150"],
        tertiary_fixed_dim: HUES.orange["400"],
        on_tertiary_fixed: HUES.orange["950"],
        on_tertiary_fixed_variant: HUES.orange["700"],

        error: stop("red", mode),
        on_error: onAccent,
        error_container: HUES.red[containerStep],
        on_error_container: HUES.red[onContainerStep],

        background: dark ? BASE.black : BASE.paper,
        on_background: dark ? BASE["200"] : BASE.black,
        surface: dark ? BASE.black : BASE.paper,
        on_surface: dark ? BASE["200"] : BASE.black,
        surface_dim: dark ? BASE.black : BASE["100"],
        surface_bright: dark ? BASE["800"] : BASE.paper,
        surface_container_lowest: dark ? BASE.black : BASE.paper,
        surface_container_low: dark ? BASE["950"] : BASE["50"],
        surface_container: dark ? BASE["900"] : BASE["100"],
        surface_container_high: dark ? BASE["850"] : BASE["150"],
        surface_container_highest: dark ? BASE["800"] : BASE["200"],
        surface_variant: dark ? BASE["900"] : BASE["100"],
        on_surface_variant: dark ? BASE["500"] : BASE["600"],
        inverse_surface: dark ? BASE["200"] : BASE.black,
        inverse_on_surface: dark ? BASE.black : BASE.paper,

        outline: dark ? BASE["700"] : BASE["300"],
        outline_variant: dark ? BASE["800"] : BASE["150"],
        scrim: BASE.black,
        shadow: BASE.black
    };

    for (var i = 0; i < HUE_NAMES.length; i++) {
        roles[HUE_NAMES[i]] = stop(HUE_NAMES[i], mode);
        roles[HUE_NAMES[i] + "_alt"] = altStop(HUE_NAMES[i], mode);
    }
    return roles;
}
