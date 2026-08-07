import QtQuick
import QtTest
import "../shell/Theme/palette.js" as P

TestCase {
    name: "Palette"
    function test_validate_ok() {
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", foregroundFaint: "#575653",
                  accent: "#4385BE", urgent: "#D14D41", warning: "#DA702C",
                  rule: "#403E3C", onAccent: "#100F0F", onUrgent: "#100F0F", onWarning: "#100F0F" };
        var r = P.validate(t);
        verify(r.ok);
        compare(r.missing.length, 0);
    }
    function test_validate_missing_key() {
        var t = { background: "#100F0F", foreground: "#CECDC3", foregroundDim: "#878580",
                  foregroundFaint: "#575653", accent: "#4385BE", urgent: "#D14D41", warning: "#DA702C",
                  rule: "#403E3C", onAccent: "#100F0F", onUrgent: "#100F0F", onWarning: "#100F0F" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("backgroundAlt") >= 0);
    }
    function test_validate_bad_hex() {
        var t = { background: "not-a-color", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", foregroundFaint: "#575653",
                  accent: "#4385BE", urgent: "#D14D41", warning: "#DA702C",
                  rule: "#403E3C", onAccent: "#100F0F", onUrgent: "#100F0F", onWarning: "#100F0F" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("background") >= 0);
    }
    function test_validate_missing_rule_and_onaccent() {
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", foregroundFaint: "#575653",
                  accent: "#4385BE", urgent: "#D14D41", warning: "#DA702C" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("rule") >= 0);
        verify(r.missing.indexOf("onAccent") >= 0);
    }
    function test_validate_missing_expansion_keys() {
        // The 2026-08-07 twelve-role expansion: foregroundFaint/warning/
        // onWarning/onUrgent are just as required as the original eight.
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41",
                  rule: "#403E3C", onAccent: "#100F0F" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("foregroundFaint") >= 0);
        verify(r.missing.indexOf("warning") >= 0);
        verify(r.missing.indexOf("onWarning") >= 0);
        verify(r.missing.indexOf("onUrgent") >= 0);
    }
    function test_fallback() {
        var f = P.fallback();
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "dark");
        compare(f.rule, "#403E3C");
        compare(f.onAccent, "#100F0F");
    }
    function test_fallback_dark_on_tokens_are_ink_not_paper() {
        // 2026-08-07 revision: dark onAccent/onUrgent/onWarning flip to ink
        // (#100F0F) — measured contrast beats paper-on-accent (3.83:1 fails
        // AA; ink measures 4.86:1). Light keeps paper on all three.
        var f = P.fallback("dark");
        compare(f.onAccent, "#100F0F");
        compare(f.onUrgent, "#100F0F");
        compare(f.onWarning, "#100F0F");
    }
    function test_fallback_no_arg_is_dark() {
        // First-boot seed and Theme.qml's absent-file default both call
        // fallback() bare — that must stay the dark variant.
        compare(JSON.stringify(P.fallback()), JSON.stringify(P.fallback("dark")));
    }
    function test_fallback_light() {
        var f = P.fallback("light");
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "light");
        compare(f.background, "#FFFCF0");
        compare(f.foreground, "#100F0F");
        compare(f.foregroundFaint, "#9F9D96");
        compare(f.accent, "#205EA6");
        compare(f.urgent, "#AF3029");
        compare(f.warning, "#BC5215");
        compare(f.rule, "#CECDC3");
        compare(f.onAccent, "#FFFCF0");
        compare(f.onUrgent, "#FFFCF0");
        compare(f.onWarning, "#FFFCF0");
    }
    function test_merge_with_fallback_fills_missing_keys() {
        // A pre-expansion theme.json written before the twelve-role
        // expansion: the original eight keys must pass through untouched,
        // the four new ones fall back individually — never the whole object.
        var old = { mode: "dark", background: "#111111", backgroundAlt: "#1C1B1A",
                    foreground: "#CECDC3", foregroundDim: "#878580",
                    accent: "#4385BE", urgent: "#D14D41",
                    rule: "#403E3C", onAccent: "#FFFCF0" };
        var m = P.mergeWithFallback(old);
        compare(m.background, "#111111");
        compare(m.rule, "#403E3C");
        // onAccent itself is an original key and passes through verbatim
        // even though the dark Flexoki default changed under it.
        compare(m.onAccent, "#FFFCF0");
        compare(m.foregroundFaint, "#575653");
        compare(m.warning, "#DA702C");
        compare(m.onWarning, "#100F0F");
        compare(m.onUrgent, "#100F0F");
    }
    function test_merge_with_fallback_rejects_bad_hex_per_key() {
        // mode:"light", so the bad rule falls back to the LIGHT variant's
        // rule — the merge fill matches the theme's own mode.
        var t = { mode: "light", background: "#111111", backgroundAlt: "#1C1B1A",
                  foreground: "#CECDC3", foregroundDim: "#878580", foregroundFaint: "#9F9D96",
                  accent: "#4385BE", urgent: "#D14D41", warning: "#BC5215",
                  rule: "not-a-color", onAccent: "#000000", onUrgent: "#000000", onWarning: "#000000" };
        var m = P.mergeWithFallback(t);
        compare(m.mode, "light");
        compare(m.rule, "#CECDC3");
        compare(m.onAccent, "#000000");
    }
    function test_merge_with_fallback_null_is_full_fallback() {
        var m = P.mergeWithFallback(null);
        compare(JSON.stringify(m), JSON.stringify(P.fallback()));
    }
}
