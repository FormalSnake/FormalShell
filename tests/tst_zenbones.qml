import QtQuick
import QtTest
import "../shell/Theme/zenbones.js" as Zenbones
import "../shell/Theme/matugen.js" as M
import "../shell/Theme/palette.js" as Palette

TestCase {
    name: "Zenbones"

    readonly property var _pin: Palette.pinnedPalette("zenbones")

    // matugen 4.1.0's own role list, same as tst_flexoki: a role missing
    // from materialRoles() is a template expression a pinned run would
    // leave on matugen's own scheme.
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
            var roles = Zenbones.materialRoles(mode);
            _matugenRoles.forEach(role => {
                verify(typeof roles[role] === "string", mode + " is missing " + role);
                verify(/^#[0-9a-f]{6}$/.test(roles[role]), mode + "." + role + " is not a hex");
            });
        });
    }

    // Every value has to come off the tone table, or a pinned run ships a
    // tone zenbones does not have.
    function test_every_value_is_on_the_tone_table() {
        var known = {};
        ["dark", "light"].forEach(mode => {
            var t = Zenbones.TONES[mode];
            Object.keys(t).forEach(k => known[t[k]] = true);
        });
        Object.keys(Zenbones.FIXED).forEach(hue => {
            var f = Zenbones.FIXED[hue];
            Object.keys(f).forEach(k => known[f[k]] = true);
        });
        ["dark", "light"].forEach(mode => {
            var roles = Zenbones.materialRoles(mode);
            Object.keys(roles).forEach(role => {
                verify(known[roles[role]] === true, mode + "." + role + " is off-table: " + roles[role]);
            });
            var b16 = Zenbones.base16(mode);
            Object.keys(b16).forEach(slot => {
                verify(known[b16[slot]] === true, mode + "." + slot + " is off-table: " + b16[slot]);
            });
        });
    }

    // Zenbones has six chromatics, so the eight hue names double up:
    // orange rides wood and purple rides blossom. `_alt` is the mode's own
    // bright variant, which is what zenbones' terminal ports spend on ANSI
    // 9-14 (unlike Flexoki, whose _alt is the other mode's stop).
    function test_hue_roles() {
        ["dark", "light"].forEach(mode => {
            var roles = Zenbones.materialRoles(mode);
            var t = Zenbones.TONES[mode];
            compare(roles.green, t.leaf);
            compare(roles.green_alt, t.leaf1);
            compare(roles.blue, t.water);
            compare(roles.blue_alt, t.water1);
            compare(roles.orange, roles.yellow);
            compare(roles.purple, roles.magenta);
        });
    }

    // The shell's own palette and the templates read one table: primary is
    // water, destructive rose, warning wood, in both directions.
    function test_shadcn_matches_material() {
        ["dark", "light"].forEach(mode => {
            var shadcn = Zenbones.shadcn(mode);
            var roles = Zenbones.materialRoles(mode);
            compare(shadcn.primary, roles.primary);
            compare(shadcn.background, roles.surface);
            compare(shadcn.foreground, roles.on_surface);
            compare(shadcn.destructive, roles.error);
            compare(shadcn.warning, roles.tertiary);
            compare(shadcn.mutedForeground, roles.on_surface_variant);
            compare(shadcn.border, roles.outline_variant);
        });
        var pin = Palette.pinnedPalette("/walls/Zenbones-forest.png");
        compare(pin.name, "zenbones");
        compare(pin.shadcn("dark").primary, Zenbones.shadcn("dark").primary);
        compare(pin.source, "6099C0");
    }

    // The upstream kitty port (extras/kitty/zenbones_{dark,light}.conf),
    // slot for slot as a terminal template renders them: the mode's own hue
    // stops for ANSI 1-6, the same mode's bright variants for 9-14, and the
    // dark scheme for black and bright white in both modes. Slots 7, 8 and
    // 15 deviate from the port on purpose: the template reads them off
    // on_surface_variant, outline and on_surface.dark, which land on the
    // dim fg, LineNr gray and full fg (the port's own 7/15 are inverted,
    // its bright white darker than white, and its 8 is the bright black
    // this table spends on outline_variant instead).
    function test_ansi_ramp_matches_the_zenbones_port() {
        var hues = ["red", "green", "yellow", "blue", "magenta", "cyan"];
        var expected = {
            dark: ["#1c1917", "#de6e7c", "#819b69", "#b77e64", "#6099c0", "#b279a7",
                "#66a5ad", "#888f94", "#685f5a", "#e8838f", "#8bae68", "#d68c67",
                "#61abda", "#cf86c1", "#65b8c1", "#b4bdc3"],
            light: ["#1c1917", "#a8334c", "#4f6c31", "#944927", "#286486", "#88507d",
                "#3b8992", "#4f5e68", "#a4968f", "#94253e", "#3f5a22", "#803d1c",
                "#1d5573", "#7b3b70", "#2b747c", "#b4bdc3"]
        };
        ["dark", "light"].forEach(mode => {
            var roles = Zenbones.materialRoles(mode);
            var dark = Zenbones.materialRoles("dark");
            var ramp = [dark.surface];
            hues.forEach(hue => ramp.push(roles[hue]));
            ramp.push(roles.on_surface_variant, roles.outline);
            hues.forEach(hue => ramp.push(roles[hue + "_alt"]));
            ramp.push(dark.on_surface);
            for (var i = 0; i < 16; i++)
                compare(ramp[i], expected[mode][i], mode + " ANSI " + i);
        });
    }

    function test_substitute_uses_zenbones_tables() {
        var out = M.substitutePinned("a={{colors.surface.default.hex}}\n"
            + "b={{ colors.primary.default.hex_stripped }}\n"
            + "e={{base16.base0B.default.hex}}\n", "dark", _pin);
        compare(out.substituted, 3);
        compare(out.skipped.length, 0);
        verify(out.text.indexOf("a=#1c1917") >= 0);
        verify(out.text.indexOf("b=6099c0") >= 0);
        verify(out.text.indexOf("e=#819b69") >= 0);
    }
}
