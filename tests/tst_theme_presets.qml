import QtQuick
import QtTest
import "../shell/Theme/presets.js" as Presets

// M49 T1 (D1): shell/Theme/presets.js's table and its resolution against a
// settings object. `resolve` takes Config.get's own signature, so the fake
// below is that function's body over a plain object, which is what keeps
// these cases honest about how the real config reads.
TestCase {
    name: "ThemePresets"

    function makeGet(settings) {
        return function (path, fallback) {
            var node = settings;
            var parts = path.split(".");
            for (var i = 0; i < parts.length; i++) {
                if (node === undefined || node === null || typeof node !== "object")
                    return fallback;
                node = node[parts[i]];
            }
            return node === undefined ? fallback : node;
        };
    }

    function test_names_are_the_two_presets() {
        compare(Presets.NAMES.length, 2);
        compare(Presets.NAMES[0], "shadcn");
        compare(Presets.NAMES[1], "retro");
    }

    function test_unknown_name_resolves_to_the_shadcn_table() {
        var t = Presets.resolve("brutalist", makeGet({}));
        compare(t.preset, "shadcn");
        compare(t.radius, 10);
        compare(t.icons, "lucide");
        compare(t.fonts, "pair");
        compare(t.surfaceOpacity, 0.85);
        compare(t.blur, true);
        compare(t.dither, false);
        compare(t.wallpaperDither, false);
        compare(t.lockDither, false);
    }

    function test_a_name_that_is_not_a_string_resolves_to_shadcn() {
        compare(Presets.defaults(undefined).radius, 10);
        compare(Presets.defaults(42).icons, "lucide");
        compare(Presets.resolve(null, makeGet({})).preset, "shadcn");
    }

    function test_retro_defaults_match_the_table() {
        var t = Presets.resolve("retro", makeGet({}));
        compare(t.preset, "retro");
        compare(t.radius, 0);
        compare(t.icons, "nerd");
        compare(t.fonts, "mono");
        compare(t.surfaceOpacity, 1);
        compare(t.blur, false);
        compare(t.dither, true);
        compare(t.wallpaperDither, true);
        compare(t.lockDither, true);
    }

    // The point of D1: a preset is a table of defaults, so one explicit key
    // moves alone and everything else stays where the preset put it.
    function test_an_explicit_key_wins_over_the_preset() {
        var t = Presets.resolve("retro", makeGet({ theme: { radius: 4 } }));
        compare(t.radius, 4);
        compare(t.icons, "nerd");
        compare(t.fonts, "mono");
    }

    function test_wallpaper_dither_can_opt_out_of_the_preset() {
        var t = Presets.resolve("retro", makeGet({ wallpaper: { dither: false } }));
        compare(t.dither, true);
        compare(t.wallpaperDither, false);
        compare(t.lockDither, true);
    }

    function test_theme_dither_carries_both_image_passes() {
        var t = Presets.resolve("shadcn", makeGet({ theme: { dither: true } }));
        compare(t.dither, true);
        compare(t.wallpaperDither, true);
        compare(t.lockDither, true);
    }

    function test_an_unknown_fonts_value_takes_the_preset_default() {
        compare(Presets.resolve("shadcn", makeGet({ theme: { fonts: "comic" } })).fonts, "pair");
        compare(Presets.resolve("retro", makeGet({ theme: { fonts: "comic" } })).fonts, "mono");
        compare(Presets.resolve("shadcn", makeGet({ theme: { fonts: "mono" } })).fonts, "mono");
    }

    // A string or a number in a boolean's place is a malformed key, not a
    // truthy one, so it reads as absent rather than as off.
    function test_a_non_boolean_takes_the_preset_default() {
        compare(Presets.resolve("shadcn", makeGet({ theme: { blur: "false" } })).blur, true);
        compare(Presets.resolve("shadcn", makeGet({ theme: { blur: 0 } })).blur, true);
        compare(Presets.resolve("retro", makeGet({ theme: { blur: 1 } })).blur, false);
        compare(Presets.resolve("shadcn", makeGet({ theme: { dither: "true" } })).dither, false);
        compare(Presets.resolve("shadcn", makeGet({ theme: { blur: false } })).blur, false);
    }

    function test_defaults_hands_back_a_copy() {
        var first = Presets.defaults("retro");
        first.radius = 99;
        compare(Presets.defaults("retro").radius, 0);
    }
}
