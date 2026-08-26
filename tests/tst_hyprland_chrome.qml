import QtQuick
import QtTest
import "../shell/Theme/chrome.js" as Chrome

TestCase {
    name: "HyprlandChrome"

    // hyprlang substitutes a $var textually, so these two lines are read back
    // by `decoration.rounding`, `blur.enabled` and every layerrule's `blur`
    // in docs/examples/hyprland/formalshell.conf. A value Hyprland cannot
    // parse there fails the whole config, not one line of it.
    function test_retro() {
        var out = Chrome.hyprlandChrome({ rounding: 0, blur: false });
        var lines = out.trim().split("\n");
        compare(lines[0].charAt(0), "#");
        compare(lines[1].charAt(0), "#");
        compare(lines.slice(2).join("\n"), "$rounding = 0\n$blur = false");
    }

    function test_shadcn() {
        var out = Chrome.hyprlandChrome({ rounding: 10, blur: true });
        compare(out.trim().split("\n").slice(2).join("\n"), "$rounding = 10\n$blur = true");
    }

    function test_rounding_is_a_non_negative_int() {
        // Hyprland's rounding is an int and rejects a negative one, and
        // theme.radius is user-set, so both have to land inside that range.
        compare(Chrome.hyprlandChrome({ rounding: 10.6, blur: false }).indexOf("$rounding = 11") >= 0, true);
        compare(Chrome.hyprlandChrome({ rounding: -4, blur: false }).indexOf("$rounding = 0") >= 0, true);
        compare(Chrome.hyprlandChrome({ rounding: "square", blur: false }).indexOf("$rounding = 0") >= 0, true);
    }

    function test_blur_is_a_real_bool() {
        compare(Chrome.hyprlandChrome({ rounding: 0, blur: "yes" }).indexOf("$blur = false") >= 0, true);
        compare(Chrome.hyprlandChrome({ rounding: 0, blur: undefined }).indexOf("$blur = false") >= 0, true);
    }

    // The Lua twin a hyprland.lua dofiles. The `return` and the table literal
    // are load-bearing: anything else comes back nil and the config silently
    // reads no rounding and no blur at all.
    function test_lua_table() {
        var out = Chrome.hyprlandChromeLua({ rounding: 10, blur: true });
        var lines = out.trim().split("\n");
        compare(lines[0].slice(0, 2), "--");
        compare(lines[1].slice(0, 2), "--");
        compare(lines[2].slice(0, 2), "--");
        compare(lines.slice(3).join("\n"),
            "return {\n"
            + "  rounding = 10,\n"
            + "  blur = true,\n"
            + "}");
        compare(Chrome.hyprlandChromeLua({ rounding: 0, blur: false }).indexOf("rounding = 0,") >= 0, true);
        compare(Chrome.hyprlandChromeLua({ rounding: 0, blur: false }).indexOf("blur = false,") >= 0, true);
    }
}
