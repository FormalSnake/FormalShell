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

    // The variables alone, with the file's own header dropped.
    function body(text) {
        var out = [];
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].charAt(0) !== "#")
                out.push(lines[i]);
        }
        return out.join("\n");
    }

    // hyprlang substitutes a $var textually, so these lines are read back by
    // `decoration.rounding`, the `shadow` block, `general`'s border and
    // every layerrule's `blur` in docs/examples/hyprland/formalshell.conf. A
    // value Hyprland cannot parse there fails the whole config, not one line
    // of it.
    function test_the_shipped_table_renders_the_shipped_chrome() {
        var out = Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 10, true));
        var lines = out.trim().split("\n");
        compare(lines[0].charAt(0), "#");
        compare(lines[1].charAt(0), "#");
        compare(lines[2].charAt(0), "#");
        compare(body(out),
            "$rounding = 10\n"
            + "$blur = true\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 8\n"
            + "$borderSize = 1\n"
            + "$borderColor = $primary\n"
            + "$shadow = false\n"
            + "$shadowRange = 4\n"
            + "$shadowPower = 3\n"
            + "$shadowOffset = 0 0\n"
            + "$shadowColor = rgba(000000ed)\n"
            + "$shadowInactiveColor = rgba(000000ed)");
    }

    // Retro is metamorphosis' chrome on square corners and no blur, which is
    // the same window role: only the two scalars move.
    function test_retro_squares_the_corners_and_keeps_the_window_chrome() {
        compare(body(Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 0, false))),
            "$rounding = 0\n"
            + "$blur = false\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 8\n"
            + "$borderSize = 1\n"
            + "$borderColor = $primary\n"
            + "$shadow = false\n"
            + "$shadowRange = 4\n"
            + "$shadowPower = 3\n"
            + "$shadowOffset = 0 0\n"
            + "$shadowColor = rgba(000000ed)\n"
            + "$shadowInactiveColor = rgba(000000ed)");
    }

    // elementary's window (M60 P7): `shadow(4)` as a compositor can draw it
    // over a 1px `border` frame, and a backdrop window differing by its
    // shadow colour alone, since Hyprland has one range and one offset for
    // every window on screen. The alphas are bytes here: 0.35 of 255 is 0x59
    // and 0.25 is 0x40.
    function test_the_pantheon_table_renders_elementarys_window() {
        compare(body(Chrome.hyprlandChrome(chromeFor(Pantheon.STYLE, 6, true))),
            "$rounding = 6\n"
            + "$blur = true\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 6\n"
            + "$borderSize = 1\n"
            + "$borderColor = $border\n"
            + "$shadow = true\n"
            + "$shadowRange = 24\n"
            + "$shadowPower = 3\n"
            + "$shadowOffset = 0 6\n"
            + "$shadowColor = rgba(00000059)\n"
            + "$shadowInactiveColor = rgba(00000040)");
    }

    function test_rounding_is_a_non_negative_int() {
        // Hyprland's rounding is an int and rejects a negative one, and
        // theme.radius is user-set, so both have to land inside that range.
        var table = Metamorphosis.STYLE;
        compare(Chrome.hyprlandChrome(chromeFor(table, 10.6, false)).indexOf("$rounding = 11") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(table, -4, false)).indexOf("$rounding = 0") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(table, "square", false)).indexOf("$rounding = 0") >= 0, true);
    }

    function test_blur_is_a_real_bool() {
        // Anything but the boolean true renders false: a stray string on a
        // hyprlang bool fails the file's parse rather than the line's.
        var table = Metamorphosis.STYLE;
        compare(Chrome.hyprlandChrome(chromeFor(table, 0, "yes")).indexOf("$blur = false") >= 0, true);
        compare(Chrome.hyprlandChrome(chromeFor(table, 0, undefined)).indexOf("$blur = false") >= 0, true);
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
        compare(body(Chrome.hyprlandChrome(wild)),
            "$rounding = 0\n"
            + "$blur = false\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 8\n"
            + "$borderSize = 20\n"
            + "$borderColor = $primary\n"
            + "$shadow = false\n"
            + "$shadowRange = 100\n"
            + "$shadowPower = 4\n"
            + "$shadowOffset = -250 0\n"
            + "$shadowColor = rgba(000000ff)\n"
            + "$shadowInactiveColor = rgba(00000000)");

        var thin = {
            rounding: 0,
            blur: false,
            window: {
                border: { color: "border", width: -3 },
                shadow: { enabled: true, range: "wide", renderPower: 0, offset: [], color: "white", alpha: 0.5 }
            },
            windowInactive: {}
        };
        compare(body(Chrome.hyprlandChrome(thin)),
            "$rounding = 0\n"
            + "$blur = false\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 8\n"
            + "$borderSize = 0\n"
            + "$borderColor = $border\n"
            + "$shadow = true\n"
            + "$shadowRange = 4\n"
            + "$shadowPower = 1\n"
            + "$shadowOffset = 0 0\n"
            + "$shadowColor = rgba(ffffff80)\n"
            + "$shadowInactiveColor = rgba(00000000)");
    }

    // A table with no window role at all loses the frame and the cast, not
    // the config's parse: every variable still renders a value Hyprland
    // takes.
    function test_a_table_with_no_window_role_still_renders_every_variable() {
        compare(body(Chrome.hyprlandChrome({ rounding: 10, blur: true })),
            "$rounding = 10\n"
            + "$blur = true\n"
            + "$gapsIn = 4\n"
            + "$gapsOut = 8\n"
            + "$borderSize = 1\n"
            + "$borderColor = rgba(00000000)\n"
            + "$shadow = false\n"
            + "$shadowRange = 4\n"
            + "$shadowPower = 3\n"
            + "$shadowOffset = 0 0\n"
            + "$shadowColor = rgba(00000000)\n"
            + "$shadowInactiveColor = rgba(00000000)");
    }

    // The Lua twin a hyprland.lua dofiles. The `return` and the table literal
    // are load-bearing: anything else comes back nil and the config silently
    // reads no chrome at all. A colour arrives as an rgba literal or as the
    // name of a role in formalshell-colors.lua, since Lua has no variable to
    // substitute.
    function test_lua_table() {
        var out = Chrome.hyprlandChromeLua(chromeFor(Pantheon.STYLE, 6, true));
        var lines = out.trim().split("\n");
        compare(lines[0].slice(0, 2), "--");
        compare(lines[1].slice(0, 2), "--");
        compare(lines[2].slice(0, 2), "--");
        compare(lines[3].slice(0, 2), "--");
        compare(lines.slice(4).join("\n"),
            "return {\n"
            + "  rounding = 6,\n"
            + "  blur = true,\n"
            + "  gapsIn = 4,\n"
            + "  gapsOut = 6,\n"
            + "  borderSize = 1,\n"
            + "  borderColor = \"border\",\n"
            + "  shadow = true,\n"
            + "  shadowRange = 24,\n"
            + "  shadowPower = 3,\n"
            + "  shadowOffset = { 0, 6 },\n"
            + "  shadowColor = \"rgba(00000059)\",\n"
            + "  shadowInactiveColor = \"rgba(00000040)\",\n"
            + "}");

        var shipped = Chrome.hyprlandChromeLua(chromeFor(Metamorphosis.STYLE, 0, false));
        compare(shipped.indexOf("rounding = 0,") >= 0, true);
        compare(shipped.indexOf("blur = false,") >= 0, true);
        compare(shipped.indexOf("shadow = false,") >= 0, true);
        compare(shipped.indexOf("borderColor = \"primary\",") >= 0, true);
        compare(shipped.indexOf("gapsIn = 4,") >= 0, true);
        compare(shipped.indexOf("gapsOut = 8,") >= 0, true);
    }

    // The gaps come off the `window` role like the frame does (M66), so a
    // look that wears no screen frame closes the outer margin it had
    // nothing left to leave room for: 4 and 8 under shadcn, 4 and 6 under
    // pantheon, and both files carry them.
    function test_each_table_publishes_its_own_gaps() {
        var shadcn = Chrome.hyprlandChrome(chromeFor(Metamorphosis.STYLE, 10, true));
        compare(shadcn.indexOf("$gapsIn = 4\n") >= 0, true);
        compare(shadcn.indexOf("$gapsOut = 8\n") >= 0, true);

        var pantheon = Chrome.hyprlandChrome(chromeFor(Pantheon.STYLE, 6, true));
        compare(pantheon.indexOf("$gapsOut = 6\n") >= 0, true);
    }

    // A table that says nothing keeps the shipped pair rather than failing
    // the file's parse, and a number outside the bound lands on it: hyprlang
    // rejects the whole config over one line.
    function test_the_gaps_are_clamped_and_fall_back() {
        var bare = { rounding: 0, blur: false, window: {}, windowInactive: {} };
        compare(Chrome.hyprlandChrome(bare).indexOf("$gapsIn = 4\n") >= 0, true);
        compare(Chrome.hyprlandChrome(bare).indexOf("$gapsOut = 8\n") >= 0, true);

        var wild = {
            rounding: 0,
            blur: false,
            window: { gapsIn: -5, gapsOut: 4000 },
            windowInactive: {}
        };
        compare(Chrome.hyprlandChrome(wild).indexOf("$gapsIn = 0\n") >= 0, true);
        compare(Chrome.hyprlandChrome(wild).indexOf("$gapsOut = 100\n") >= 0, true);
    }
}
