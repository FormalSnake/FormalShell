.pragma library
.import "style.js" as Style

// The chrome a Hyprland config reads back out of
// ~/.config/hypr/formalshell-chrome.lua: the window rounding, whether
// the compositor blurs behind the shell's surfaces, and the gaps, frame and
// cast the theme table's `window` role asks for (M60 P7). Not a matugen template
// like the colours are, because a template only ever sees the wallpaper's
// palette and none of this comes from there: the first two are settings.json
// keys and the rest is the live table, so ThemeEngine renders and publishes
// it itself.
//
// Every value here is clamped to the range Hyprland's own option carries
// (src/config/values/ConfigValues.cpp, 0.56), because a value outside it
// fails the whole hl.config call rather than one key: `decoration:rounding` 0..20,
// `decoration:shadow:range` 0..100, `:render_power` 1..4, `:offset` a vec2
// of -250..250, `general:border_size` 0..20.

// Hyprland's `rounding` is an int and rejects a negative one, so a hand-set
// theme.radius that is fractional or below zero still has to land on a value
// the config accepts. NaN falls through the comparison to 0.
function _rounding(value) {
    var n = Math.round(Number(value));
    return n > 0 ? n : 0;
}

// Anything that is not the boolean true renders false: `enabled =` and the
// layer rules' `blur =` take a bool, and a stray string or number reaching
// them would be rejected.
function _blur(value) {
    return value === true;
}

function _int(value, min, max, fallback) {
    var n = Math.round(Number(value));
    if (!isFinite(n))
        return fallback;
    return Math.min(max, Math.max(min, n));
}

function _byte(alpha) {
    var a = Number(alpha);
    if (!isFinite(a))
        return "ff";
    var b = Math.round(Math.min(1, Math.max(0, a)) * 255);
    return (b < 16 ? "0" : "") + b.toString(16);
}

// One colour, as the Lua table carries it. The two literals a table carries
// render as `rgba(RRGGBBAA)`, Hyprland's own 8-digit hex form; anything else
// is a palette role and renders as its name, a key into
// formalshell-colors.lua's own table (`colors[c] or c` reads both), so the
// wallpaper keeps moving it without this file being rewritten at all.
//
// A role therefore arrives at whatever alpha the palette gave it: there is
// no arithmetic to put one on a colour looked up by name.
function _color(name, alpha) {
    if (name === undefined || name === null || name === "transparent")
        return "rgba(00000000)";
    var literal = Style.LITERAL_COLORS[name];
    if (literal === undefined)
        return name;
    return "rgba(" + literal.replace("#", "") + _byte(alpha) + ")";
}

// The `window` role's two states rendered into the values the table
// below carries. Hyprland draws one cast for every window on screen and gives
// the unfocused ones a colour of their own, so the focused state sets the
// range, the power and the offset and the backdrop state is read for its
// colour alone.
//
// A table with no frame at all loses the frame rather than the config: the
// size falls back to Hyprland's own default and the colour to nothing.
//
// The two gaps are the theme's own spacing between windows and round them
// (owner, 2026-09-18), so a look that drops the screen frame closes the
// margin it was leaving room for. `general:gaps_in` and `gaps_out` are a
// custom gaps type rather than an option with a declared range, so the
// 0..100 bound here is ours: past that a table has a typo, not a look.
function _window(chrome) {
    var focused = chrome.window || {};
    var backdrop = chrome.windowInactive || {};
    var border = focused.border || {};
    var cast = focused.shadow || {};
    var backdropCast = backdrop.shadow || {};
    return {
        gapsIn: _int(focused.gapsIn, 0, 100, 4),
        gapsOut: _int(focused.gapsOut, 0, 100, 8),
        borderSize: _int(border.width, 0, 20, 1),
        borderColor: _color(border.color, border.alpha),
        enabled: _blur(cast.enabled),
        range: _int(cast.range, 0, 100, 4),
        power: _int(cast.renderPower, 1, 4, 3),
        offset: _int((cast.offset || [])[0], -250, 250, 0)
            + " " + _int((cast.offset || [])[1], -250, 250, 0),
        color: _color(cast.color, cast.alpha),
        backdropColor: _color(backdropCast.color, backdropCast.alpha)
    };
}

function hyprlandChrome(chrome) {
    var w = _window(chrome);
    return "-- Written by the shell (ThemeEngine) into ~/.config/hypr/formalshell-chrome.lua\n"
        + "-- on every theme.radius/theme.blur/theme.preset change, for a hyprland.lua\n"
        + "-- that reads it back with `dofile`. The shell asks Hyprland to reload after\n"
        + "-- each write.\n"
        + "return {\n"
        + "  rounding = " + _rounding(chrome.rounding) + ",\n"
        + "  blur = " + _blur(chrome.blur) + ",\n"
        + "  gapsIn = " + w.gapsIn + ",\n"
        + "  gapsOut = " + w.gapsOut + ",\n"
        + "  borderSize = " + w.borderSize + ",\n"
        + "  borderColor = \"" + w.borderColor + "\",\n"
        + "  shadow = " + w.enabled + ",\n"
        + "  shadowRange = " + w.range + ",\n"
        + "  shadowPower = " + w.power + ",\n"
        + "  shadowOffset = { " + w.offset.split(" ").join(", ") + " },\n"
        + "  shadowColor = \"" + w.color + "\",\n"
        + "  shadowInactiveColor = \"" + w.backdropColor + "\",\n"
        + "}\n";
}
