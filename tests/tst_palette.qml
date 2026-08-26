import QtQuick
import QtTest
import "../shell/Theme/palette.js" as P

TestCase {
    name: "Palette"

    readonly property var _validDark: ({
        background: "#09090b", foreground: "#fafafa",
        card: "#18181b", cardForeground: "#fafafa",
        popover: "#18181b", popoverForeground: "#fafafa",
        primary: "#e4e4e7", primaryForeground: "#18181b",
        secondary: "#27272a", secondaryForeground: "#fafafa",
        muted: "#27272a", mutedForeground: "#a1a1aa",
        accent: "#27272a", accentForeground: "#fafafa",
        destructive: "#ff6467", destructiveForeground: "#fafafa",
        warning: "#fbbf24", warningForeground: "#18181b",
        border: "#27272a", input: "#3f3f46", ring: "#71717a",
        chart1: "#e4e4e7", chart2: "#27272a", chart3: "#fbbf24",
        chart4: "#3f3f46", chart5: "#71717a"
    })

    function test_validate_ok() {
        var r = P.validate(_validDark);
        verify(r.ok);
        compare(r.missing.length, 0);
    }

    function test_validate_missing_key() {
        var t = Object.assign({}, _validDark);
        delete t.card;
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("card") >= 0);
    }

    function test_validate_bad_hex() {
        var t = Object.assign({}, _validDark, { background: "not-a-color" });
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("background") >= 0);
    }

    function test_validate_missing_several_keys() {
        var t = Object.assign({}, _validDark);
        delete t.border;
        delete t.ring;
        delete t.chart5;
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("border") >= 0);
        verify(r.missing.indexOf("ring") >= 0);
        verify(r.missing.indexOf("chart5") >= 0);
    }

    function test_validate_empty_object_reports_every_key() {
        var r = P.validate({});
        verify(!r.ok);
        compare(r.missing.length, P.COLOR_KEYS.length);
    }

    function test_fallback() {
        var f = P.fallback();
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "dark");
        compare(f.border, "#27272a");
        compare(f.primaryForeground, "#18181b");
    }

    function test_fallback_no_arg_is_dark() {
        // First-boot seed and Theme.qml's absent-file default both call
        // fallback() bare, that must stay the dark variant.
        compare(JSON.stringify(P.fallback()), JSON.stringify(P.fallback("dark")));
    }

    // shadcn's own zinc palette (spec "Visual system > Color" table,
    // 2026-08-25 redesign). primary carries the wallpaper's own color under
    // matugen; accent is a neutral hover fill, distinct from primary.
    function test_fallback_dark_matches_the_spec_table() {
        var f = P.fallback("dark");
        compare(f.background, "#09090b");
        compare(f.foreground, "#fafafa");
        compare(f.card, "#18181b");
        compare(f.primary, "#e4e4e7");
        compare(f.primaryForeground, "#18181b");
        compare(f.mutedForeground, "#a1a1aa");
        compare(f.accent, "#27272a");
        compare(f.destructive, "#ff6467");
        compare(f.warning, "#fbbf24");
        compare(f.warningForeground, "#18181b");
        compare(f.border, "#27272a");
        compare(f.ring, "#71717a");
    }

    function test_fallback_light() {
        var f = P.fallback("light");
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "light");
        compare(f.background, "#ffffff");
        compare(f.foreground, "#09090b");
        compare(f.card, "#ffffff");
        compare(f.primary, "#18181b");
        compare(f.primaryForeground, "#fafafa");
        compare(f.mutedForeground, "#71717a");
        compare(f.accent, "#f4f4f5");
        compare(f.destructive, "#e7000b");
        compare(f.warning, "#d97706");
        compare(f.border, "#e4e4e7");
        compare(f.ring, "#a1a1aa");
    }

    // Flexoki on the same role set: black/b950/b900 surfaces, blue-400 as
    // primary and ring, b800 borders. Every role validates so the static
    // write path can hand it to theme.json unchanged.
    function test_flexoki_dark() {
        var f = P.flexoki("dark");
        verify(P.validate(f).ok);
        compare(f.mode, "dark");
        compare(f.background, "#100f0f");
        compare(f.card, "#1c1b1a");
        compare(f.foreground, "#cecdc3");
        compare(f.primary, "#4385be");
        compare(f.ring, "#4385be");
        compare(f.border, "#403e3c");
        compare(f.destructive, "#d14d41");
        compare(f.warning, "#da702c");
        // The source a pinned matugen run is seeded with is the dark primary
        // itself, so the user's templates and the shell agree on the hue.
        compare("#" + P.FLEXOKI_SOURCE.toLowerCase(), f.primary);
    }

    function test_flexoki_light() {
        var f = P.flexoki("light");
        verify(P.validate(f).ok);
        compare(f.mode, "light");
        compare(f.background, "#fffcf0");
        compare(f.card, "#f2f0e5");
        compare(f.foreground, "#100f0f");
        compare(f.primary, "#205ea6");
        compare(f.ring, "#205ea6");
        compare(f.border, "#dad8ce");
        compare(f.destructive, "#af3029");
        compare(f.warning, "#bc5215");
    }

    function test_flexoki_no_arg_is_dark() {
        compare(JSON.stringify(P.flexoki()), JSON.stringify(P.flexoki("dark")));
    }

    function test_pins_flexoki_is_a_case_insensitive_path_substring() {
        verify(P.pinsFlexoki("/w/dark/Moraine_Lake-flexoki.webp"));
        verify(P.pinsFlexoki("/w/dark/FLEXOKI-dark-orb.png"));
        verify(P.pinsFlexoki("/w/flexoki/anything.png"));
        verify(!P.pinsFlexoki("/w/dark/wallhaven-yq2zwl.png"));
        verify(!P.pinsFlexoki(""));
        verify(!P.pinsFlexoki(null));
    }

    function test_merge_with_fallback_fills_missing_keys() {
        // A theme.json written before a role existed: the roles it does
        // carry pass through untouched, the ones it lacks fall back
        // individually, never the whole object.
        var old = { mode: "dark", background: "#111111", foreground: "#fafafa",
                    card: "#18181b", primary: "#e4e4e7", primaryForeground: "#222222" };
        var m = P.mergeWithFallback(old);
        compare(m.background, "#111111");
        // primaryForeground itself is present and passes through verbatim
        // even though the dark zinc default differs from it.
        compare(m.primaryForeground, "#222222");
        compare(m.border, "#27272a");
        compare(m.mutedForeground, "#a1a1aa");
        compare(m.warning, "#fbbf24");
        compare(m.warningForeground, "#18181b");
        compare(m.destructiveForeground, "#fafafa");
    }

    function test_merge_with_fallback_rejects_bad_hex_per_key() {
        // mode:"light", so the bad border falls back to the LIGHT variant's
        // border, the merge fill matches the theme's own mode.
        var t = Object.assign({}, _validDark, { mode: "light", border: "not-a-color", primaryForeground: "#000000" });
        var m = P.mergeWithFallback(t);
        compare(m.mode, "light");
        compare(m.border, "#e4e4e7");
        compare(m.primaryForeground, "#000000");
    }

    function test_merge_with_fallback_null_is_full_fallback() {
        var m = P.mergeWithFallback(null);
        compare(JSON.stringify(m), JSON.stringify(P.fallback()));
    }
}
