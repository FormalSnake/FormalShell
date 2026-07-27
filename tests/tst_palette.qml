import QtQuick
import QtTest
import "../shell/Theme/palette.js" as P

TestCase {
    name: "Palette"
    function test_validate_ok() {
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41",
                  rule: "#403E3C", onAccent: "#FFFCF0" };
        var r = P.validate(t);
        verify(r.ok);
        compare(r.missing.length, 0);
    }
    function test_validate_missing_key() {
        var t = { background: "#100F0F", foreground: "#CECDC3", foregroundDim: "#878580",
                  accent: "#4385BE", urgent: "#D14D41", rule: "#403E3C", onAccent: "#FFFCF0" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("backgroundAlt") >= 0);
    }
    function test_validate_bad_hex() {
        var t = { background: "not-a-color", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41",
                  rule: "#403E3C", onAccent: "#FFFCF0" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("background") >= 0);
    }
    function test_validate_missing_rule_and_onaccent() {
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("rule") >= 0);
        verify(r.missing.indexOf("onAccent") >= 0);
    }
    function test_fallback() {
        var f = P.fallback();
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "dark");
        compare(f.rule, "#403E3C");
        compare(f.onAccent, "#FFFCF0");
    }
    function test_merge_with_fallback_fills_missing_keys() {
        // An old theme.json written before rule/onAccent existed: the six
        // original keys must pass through untouched, the two new ones fall
        // back individually — never the whole object.
        var old = { mode: "dark", background: "#111111", backgroundAlt: "#1C1B1A",
                    foreground: "#CECDC3", foregroundDim: "#878580",
                    accent: "#4385BE", urgent: "#D14D41" };
        var m = P.mergeWithFallback(old);
        compare(m.background, "#111111");
        compare(m.rule, "#403E3C");
        compare(m.onAccent, "#FFFCF0");
    }
    function test_merge_with_fallback_rejects_bad_hex_per_key() {
        var t = { mode: "light", background: "#111111", backgroundAlt: "#1C1B1A",
                  foreground: "#CECDC3", foregroundDim: "#878580",
                  accent: "#4385BE", urgent: "#D14D41",
                  rule: "not-a-color", onAccent: "#000000" };
        var m = P.mergeWithFallback(t);
        compare(m.mode, "light");
        compare(m.rule, "#403E3C");
        compare(m.onAccent, "#000000");
    }
    function test_merge_with_fallback_null_is_full_fallback() {
        var m = P.mergeWithFallback(null);
        compare(JSON.stringify(m), JSON.stringify(P.fallback()));
    }
}
