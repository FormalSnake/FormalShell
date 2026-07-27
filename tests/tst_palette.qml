import QtQuick
import QtTest
import "../shell/Theme/palette.js" as P

TestCase {
    name: "Palette"
    function test_validate_ok() {
        var t = { background: "#100F0F", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41" };
        var r = P.validate(t);
        verify(r.ok);
        compare(r.missing.length, 0);
    }
    function test_validate_missing_key() {
        var t = { background: "#100F0F", foreground: "#CECDC3", foregroundDim: "#878580",
                  accent: "#4385BE", urgent: "#D14D41" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("backgroundAlt") >= 0);
    }
    function test_validate_bad_hex() {
        var t = { background: "not-a-color", backgroundAlt: "#1C1B1A", foreground: "#CECDC3",
                  foregroundDim: "#878580", accent: "#4385BE", urgent: "#D14D41" };
        var r = P.validate(t);
        verify(!r.ok);
        verify(r.missing.indexOf("background") >= 0);
    }
    function test_fallback() {
        var f = P.fallback();
        var r = P.validate(f);
        verify(r.ok);
        compare(f.mode, "dark");
    }
}
