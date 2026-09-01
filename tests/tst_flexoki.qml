import QtQuick
import QtTest
import "../shell/Theme/flexoki.js" as Flexoki
import "../shell/Theme/matugen.js" as M
import "../shell/Theme/palette.js" as Palette

TestCase {
    name: "Flexoki"

    readonly property var _pin: Palette.pinnedPalette("flexoki")

    // matugen 4.1.0's own role list, read off `matugen -j hex --dry-run
    // color hex <x>` against a bare config. A role missing from
    // materialRoles() is a template expression a pinned run would leave on
    // matugen's blue scheme, so the whole list is asserted rather than
    // sampled.
    readonly property var _matugenRoles: ["background", "error", "error_container",
        "inverse_on_surface", "inverse_primary", "inverse_surface", "on_background",
        "on_error", "on_error_container", "on_primary", "on_primary_container",
        "on_primary_fixed", "on_primary_fixed_variant", "on_secondary",
        "on_secondary_container", "on_secondary_fixed", "on_secondary_fixed_variant",
        "on_surface", "on_surface_variant", "on_tertiary", "on_tertiary_container",
        "on_tertiary_fixed", "on_tertiary_fixed_variant", "outline", "outline_variant",
        "primary", "primary_container", "primary_fixed", "primary_fixed_dim", "scrim",
        "secondary", "secondary_container", "secondary_fixed", "secondary_fixed_dim",
        "shadow", "source_color", "surface", "surface_bright", "surface_container",
        "surface_container_high", "surface_container_highest", "surface_container_low",
        "surface_container_lowest", "surface_dim", "surface_tint", "surface_variant",
        "tertiary", "tertiary_container", "tertiary_fixed", "tertiary_fixed_dim"]

    function test_material_roles_cover_matugen() {
        ["dark", "light"].forEach(mode => {
            var roles = Flexoki.materialRoles(mode);
            _matugenRoles.forEach(role => {
                verify(typeof roles[role] === "string", mode + " is missing " + role);
                verify(/^#[0-9a-f]{6}$/.test(roles[role]), mode + "." + role + " is not a hex");
            });
        });
    }

    // Every value has to come off the ramp, or a pinned run ships a tone
    // Flexoki does not have.
    function test_every_value_is_on_the_ramp() {
        var known = {};
        Object.keys(Flexoki.BASE).forEach(k => known[Flexoki.BASE[k]] = true);
        Flexoki.HUE_NAMES.forEach(hue => {
            Object.keys(Flexoki.HUES[hue]).forEach(step => known[Flexoki.HUES[hue][step]] = true);
        });
        ["dark", "light"].forEach(mode => {
            var roles = Flexoki.materialRoles(mode);
            Object.keys(roles).forEach(role => {
                verify(known[roles[role]] === true, mode + "." + role + " is off-ramp: " + roles[role]);
            });
            var b16 = Flexoki.base16(mode);
            Object.keys(b16).forEach(slot => {
                verify(known[b16[slot]] === true, mode + "." + slot + " is off-ramp: " + b16[slot]);
            });
        });
    }

    // Material has no green or yellow, so a terminal template reads its ANSI
    // ramp off these eight instead. The `_alt` twin is the other mode's stop,
    // which is what Flexoki's own terminal ports spend on ANSI 9-14.
    function test_hue_roles() {
        var dark = Flexoki.materialRoles("dark");
        var light = Flexoki.materialRoles("light");
        compare(dark.green, Flexoki.HUES.green["400"]);
        compare(dark.green_alt, Flexoki.HUES.green["600"]);
        compare(light.green, Flexoki.HUES.green["600"]);
        compare(light.green_alt, Flexoki.HUES.green["400"]);
        compare(dark.yellow, Flexoki.HUES.yellow["400"]);
    }

    // The shell's own palette and the templates read one table: primary is
    // blue, destructive red, warning orange, in both directions.
    function test_shadcn_matches_material() {
        ["dark", "light"].forEach(mode => {
            var shadcn = Flexoki.shadcn(mode);
            var roles = Flexoki.materialRoles(mode);
            compare(shadcn.primary, roles.primary);
            compare(shadcn.background, roles.surface);
            compare(shadcn.foreground, roles.on_surface);
            compare(shadcn.destructive, roles.error);
            compare(shadcn.warning, roles.tertiary);
            compare(shadcn.mutedForeground, roles.on_surface_variant);
            compare(shadcn.border, roles.outline_variant);
        });
        var pin = Palette.pinnedPalette("/walls/Flexoki-dune.png");
        compare(pin.name, "flexoki");
        compare(pin.shadcn("dark").primary, Flexoki.shadcn("dark").primary);
        compare(pin.source, "4385BE");
        compare(Palette.pinnedPalette("/walls/dune.png"), null);
    }

    // Ghostty's bundled Flexoki Dark/Light, slot for slot. A terminal template
    // reads its 16 off these roles, so this pins the roles rather than the
    // template: the mode's own hue stop for ANSI 1-6, the other mode's for
    // 9-14, and the dark scheme for black and bright white in both modes.
    function test_ansi_ramp_matches_the_flexoki_port() {
        var hues = ["red", "green", "yellow", "blue", "magenta", "cyan"];
        var expected = {
            dark: ["#100f0f", "#d14d41", "#879a39", "#d0a215", "#4385be", "#ce5d97",
                "#3aa99f", "#878580", "#575653", "#af3029", "#66800b", "#ad8301",
                "#205ea6", "#a02f6f", "#24837b", "#cecdc3"],
            light: ["#100f0f", "#af3029", "#66800b", "#ad8301", "#205ea6", "#a02f6f",
                "#24837b", "#6f6e69", "#b7b5ac", "#d14d41", "#879a39", "#d0a215",
                "#4385be", "#ce5d97", "#3aa99f", "#cecdc3"]
        };
        ["dark", "light"].forEach(mode => {
            var roles = Flexoki.materialRoles(mode);
            var dark = Flexoki.materialRoles("dark");
            var ramp = [dark.surface];
            hues.forEach(hue => ramp.push(roles[hue]));
            ramp.push(roles.on_surface_variant, roles.outline);
            hues.forEach(hue => ramp.push(roles[hue + "_alt"]));
            ramp.push(dark.on_surface);
            for (var i = 0; i < 16; i++)
                compare(ramp[i], expected[mode][i], mode + " ANSI " + i);
        });
    }

    function test_substitute_formats() {
        var out = M.substitutePinned("a={{colors.surface.default.hex}}\n"
            + "b={{ colors.primary.default.hex_stripped }}\n"
            + "c={{colors.error.default.rgb}}\n"
            + "d={{colors.surface.default.rgba}}\n"
            + "e={{base16.base0B.default.hex}}\n", "dark", _pin);
        compare(out.substituted, 5);
        compare(out.skipped.length, 0);
        verify(out.text.indexOf("a=#100f0f") >= 0);
        verify(out.text.indexOf("b=4385be") >= 0);
        verify(out.text.indexOf("c=rgb(209, 77, 65)") >= 0);
        verify(out.text.indexOf("d=rgba(16, 15, 15, 1)") >= 0);
        // base0B is green in Flexoki's own base16, which is the whole point:
        // a terminal reading it gets green where matugen's scheme has none.
        verify(out.text.indexOf("e=#879a39") >= 0);
    }

    function test_substitute_leaves_matugens_own_keywords() {
        var src = "m={{mode}} i={{image}} u={{colors.made_up.default.hex}}\n";
        var out = M.substitutePinned(src, "dark", _pin);
        compare(out.text, src);
        compare(out.substituted, 0);
        compare(out.skipped.length, 1);
    }

    // matugen 4.1.0 rejects a colour filter on a bare string, so a filtered
    // .hex goes through to_color and anything else keeps matugen's value
    // rather than rendering in the wrong syntax.
    function test_substitute_filters() {
        var out = M.substitutePinned("a={{ colors.primary.default.hex | set_lightness: -20.0 }}\n"
            + "b={{ colors.primary.default.rgb | set_lightness: -20.0 }}\n", "dark", _pin);
        verify(out.text.indexOf('a={{ "#4385be" | to_color | set_lightness: -20.0 }}') >= 0);
        verify(out.text.indexOf("b={{ colors.primary.default.rgb | set_lightness: -20.0 }}") >= 0);
        compare(out.skipped.length, 1);
    }

    function test_scheme_selects_the_table() {
        var out = M.substitutePinned("d={{colors.primary.dark.hex}} l={{colors.primary.light.hex}} "
            + "x={{colors.primary.default.hex}}", "light", _pin);
        verify(out.text.indexOf("d=#4385be") >= 0);
        verify(out.text.indexOf("l=#205ea6") >= 0);
        verify(out.text.indexOf("x=#205ea6") >= 0);
    }

    function test_template_inputs_round_trip() {
        var cfg = "[templates.a]\ninput_path = '~/.config/matugen/templates/a.tmpl'\n"
            + "output_path = '~/a'\n[templates.b]\ninput_path = \"/abs/b.tmpl\"\n";
        var inputs = M.templateInputs(cfg);
        compare(inputs.length, 2);
        compare(M.expandHome(inputs[0], "/home/u"), "/home/u/.config/matugen/templates/a.tmpl");
        compare(M.expandHome(inputs[1], "/home/u"), "/abs/b.tmpl");
        var out = M.rewriteTemplateInputs(cfg, (path, index) => index === 0 ? "/state/0.tmpl" : null);
        verify(out.indexOf("input_path = '/state/0.tmpl'") >= 0);
        verify(out.indexOf('input_path = "/abs/b.tmpl"') >= 0);
        // output_path is matugen's to resolve, never repointed.
        verify(out.indexOf("output_path = '~/a'") >= 0);
    }
}
