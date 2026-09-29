import QtQuick
import QtTest
import "../shell/Theme/chrome.js" as Chrome
import "../shell/Theme/style.js" as Style
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/pantheon.js" as Pantheon

TestCase {
    name: "HyprlandChrome"

    // What ThemeEngine hands the renderer: the two scalars settings.json
    // owns and the `window` role's two states straight off the live table.
    function chromeFor(table, rounding, blur) {
        return {
            rounding: rounding,
            blur: blur,
            window: Style.entry(table, "window", "rest"),
            windowInactive: Style.entry(table, "window", "inactive")
        };
    }

    // The table alone, with the file's own header dropped.
    function body(text) {
        var out = [];
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].slice(0, 2) !== "--")
                out.push(lines[i]);
        }
        return out.join("\n");
    }

    function expected(o) {
        var keys = ["rounding", "blur", "gapsIn", "gapsOut", "borderSize", "borderColor", "shadow",
            "shadowRange", "shadowPower", "shadowOffset", "shadowColor", "shadowInactiveColor"];
        var out = "return {\n";
        for (var i = 0; i < keys.length; i++)
            out += "  " + keys[i] + " = " + o[keys[i]] + ",\n";
        return out + "}";
    }

    // The values are read back by `hl.config`'s decoration, shadow and
    // general blocks and every layer rule's `blur` in
    // docs/examples/hyprland/formalshell.lua. The `return` and the table
    // literal are load-bearing: anything else comes back nil and the config
    // silently reads no chrome at all.
    function test_the_shipped_table_renders_the_shipped_chrome() {
        var out = Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 10, true));
        var lines = out.trim().split("\n");
        compare(lines[0].slice(0, 2), "--");
        compare(lines[1].slice(0, 2), "--");
        compare(lines[2].slice(0, 2), "--");
        compare(lines[3].slice(0, 2), "--");
        compare(body(out), expected({
            rounding: 10, blur: "true", gapsIn: 4, gapsOut: 8, borderSize: 1,
            borderColor: '"primary"', shadow: "false", shadowRange: 4, shadowPower: 3,
            shadowOffset: "{ 0, 0 }", shadowColor: '"rgba(000000ed)"',
            shadowInactiveColor: '"rgba(000000ed)"'
        }));
    }

    // Retro is metamorphosis' chrome on square corners and no blur, which is
    // the same window role: only the two scalars move.
    function test_retro_squares_the_corners_and_keeps_the_window_chrome() {
        compare(body(Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 0, false))), expected({
            rounding: 0, blur: "false", gapsIn: 4, gapsOut: 8, borderSize: 1,
            borderColor: '"primary"', shadow: "false", shadowRange: 4, shadowPower: 3,
            shadowOffset: "{ 0, 0 }", shadowColor: '"rgba(000000ed)"',
            shadowInactiveColor: '"rgba(000000ed)"'
        }));
    }

    // elementary's window (M60 P7): `shadow(4)` as a compositor can draw it
    // over a 1px `border` frame, and a backdrop window differing by its
    // shadow colour alone, since Hyprland has one range and one offset for
    // every window on screen. The alphas are bytes here: 0.35 of 255 is 0x59
    // and 0.25 is 0x40. A colour arrives as an rgba literal or as the name of
    // a role in formalshell-colors.lua.
    function test_the_pantheon_table_renders_elementarys_window() {
        compare(body(Chrome.hyprlandChrome(chromeFor(Pantheon.STYLE, 6, true))), expected({
            rounding: 6, blur: "true", gapsIn: 4, gapsOut: 6, borderSize: 1,
            borderColor: '"border"', shadow: "true", shadowRange: 24, shadowPower: 3,
            shadowOffset: "{ 0, 6 }", shadowColor: '"rgba(00000059)"',
            shadowInactiveColor: '"rgba(00000040)"'
        }));
    }

    function test_rounding_is_a_non_negative_int() {
        // Hyprland's rounding is an int and rejects a negative one, and
        // theme.radius is user-set, so both have to land inside that range.
        var t = Metamorphosis.STYLE;
        compare(Chrome.hyprlandChrome(chromeFor(t, 10.6, false)).indexOf("rounding = 11,") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(t, -4, false)).indexOf("rounding = 0,") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(t, "square", false)).indexOf("rounding = 0,") >= 0, true);
    }

    function test_blur_is_a_real_bool() {
        // Anything but the boolean true renders false: a stray string on a
        // bool option is rejected.
        var t = Metamorphosis.STYLE;
        compare(Chrome.hyprlandChrome(chromeFor(t, 0, "yes")).indexOf("blur = false,") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(t, 0, undefined)).indexOf("blur = false,") >= 0, true);
    }

    // Every window value lands inside the range Hyprland's own option
    // carries (ConfigValues.cpp, 0.56), whatever the table said: range
    // 0..100, render_power 1..4, the offset a vec2 of -250..250, border_size
    // 0..20, and the switch a real bool.
    function test_the_window_values_are_clamped_to_hyprlands_own_ranges() {
        var wild = {
            rounding: 0,
            blur: false,
            window: {
                border: { color: "primary", width: 99 },
                shadow: {
                    enabled: "on",
                    range: 4000,
                    renderPower: 9,
                    offset: [-999, "down"],
                    color: "black",
                    alpha: 4
                }
            },
            windowInactive: { shadow: { color: "black", alpha: -1 } }
        };
        compare(body(Chrome.hyprlandChrome(wild)), expected({
            rounding: 0, blur: "false", gapsIn: 4, gapsOut: 8, borderSize: 20,
            borderColor: '"primary"', shadow: "false", shadowRange: 100, shadowPower: 4,
            shadowOffset: "{ -250, 0 }", shadowColor: '"rgba(000000ff)"',
            shadowInactiveColor: '"rgba(00000000)"'
        }));

        var thin = {
            rounding: 0,
            blur: false,
            window: {
                border: { color: "border", width: -3 },
                shadow: { enabled: true, range: "wide", renderPower: 0, offset: [], color: "white", alpha: 0.5 }
            },
            windowInactive: {}
        };
        compare(body(Chrome.hyprlandChrome(thin)), expected({
            rounding: 0, blur: "false", gapsIn: 4, gapsOut: 8, borderSize: 0,
            borderColor: '"border"', shadow: "true", shadowRange: 4, shadowPower: 1,
            shadowOffset: "{ 0, 0 }", shadowColor: '"rgba(ffffff80)"',
            shadowInactiveColor: '"rgba(00000000)"'
        }));
    }

    // A table with no window role at all loses the frame and the cast, not
    // the config: every key still renders a value Hyprland takes.
    function test_a_table_with_no_window_role_still_renders_every_key() {
        compare(body(Chrome.hyprlandChrome({ rounding: 10, blur: true })), expected({
            rounding: 10, blur: "true", gapsIn: 4, gapsOut: 8, borderSize: 1,
            borderColor: '"rgba(00000000)"', shadow: "false", shadowRange: 4, shadowPower: 3,
            shadowOffset: "{ 0, 0 }", shadowColor: '"rgba(00000000)"',
            shadowInactiveColor: '"rgba(00000000)"'
        }));
    }

    // The gaps come off the `window` role like the frame does (M66), so a
    // look that wears no screen frame closes the outer margin it had
    // nothing left to leave room for: 4 and 8 under shadcn, 4 and 6 under
    // pantheon.
    function test_each_table_publishes_its_own_gaps() {
        var shadcn = Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 10, true));
        compare(shadcn.indexOf("gapsIn = 4,\n") >= 0, true);
        compare(shadcn.indexOf("gapsOut = 8,\n") >= 0, true);

        var pantheon = Chrome.hyprlandChrome(chromeFor(Pantheon.STYLE, 6, true));
        compare(pantheon.indexOf("gapsOut = 6,\n") >= 0, true);
    }

    // A table that says nothing keeps the shipped pair, and a number outside
    // the bound lands on it.
    function test_the_gaps_are_clamped_and_fall_back() {
        var bare = { rounding: 0, blur: false, window: {}, windowInactive: {} };
        compare(Chrome.hyprlandChrome(bare).indexOf("gapsIn = 4,\n") >= 0, true);
        compare(Chrome.hyprlandChrome(bare).indexOf("gapsOut = 8,\n") >= 0, true);

        var wild = {
            rounding: 0,
            blur: false,
            window: { gapsIn: -5, gapsOut: 4000 },
            windowInactive: {}
        };
        compare(Chrome.hyprlandChrome(wild).indexOf("gapsIn = 0,\n") >= 0, true);
        compare(Chrome.hyprlandChrome(wild).indexOf("gapsOut = 100,\n") >= 0, true);
    }
}
