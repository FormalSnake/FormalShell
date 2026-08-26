.pragma library

// The two chrome values a Hyprland config reads back out of
// ~/.config/hypr/formalshell-chrome.{conf,lua}: the window rounding and
// whether the compositor blurs behind the shell's surfaces. Not a matugen
// template like the colours are, because a template only ever sees the
// wallpaper's palette and both of these come from settings.json, so
// ThemeEngine renders and publishes them itself.

// Hyprland's `rounding` is an int and rejects a negative one, so a hand-set
// theme.radius that is fractional or below zero still has to land on a value
// the config parses. NaN falls through the comparison to 0.
function _rounding(value) {
    var n = Math.round(Number(value));
    return n > 0 ? n : 0;
}

// Anything that is not the boolean true renders false: `enabled =` and the
// layer rules' `blur =` take a hyprlang bool, and a stray string or number
// reaching them would fail the whole file's parse rather than one line's.
function _blur(value) {
    return value === true;
}

function hyprlandChrome(chrome) {
    return "# Written by the shell (ThemeEngine) into ~/.config/hypr/formalshell-chrome.conf\n"
        + "# on every theme.radius/theme.blur change; `source` it from hyprland.conf.\n"
        + "$rounding = " + _rounding(chrome.rounding) + "\n"
        + "$blur = " + _blur(chrome.blur) + "\n";
}

// Hyprland 0.55 replaced hyprlang with Lua, and a Lua config cannot source
// hyprlang, so the same two values also ship as a table a `dofile` returns.
function hyprlandChromeLua(chrome) {
    return "-- Written by the shell (ThemeEngine) into ~/.config/hypr/formalshell-chrome.lua\n"
        + "-- on every theme.radius/theme.blur change, for a hyprland.lua that reads it\n"
        + "-- back with `dofile`. The shell asks Hyprland to reload after each write.\n"
        + "return {\n"
        + "  rounding = " + _rounding(chrome.rounding) + ",\n"
        + "  blur = " + _blur(chrome.blur) + ",\n"
        + "}\n";
}
