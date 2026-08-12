import QtQuick
import QtTest
import "../shell/HotCorners/corners.js" as Corners

TestCase {
    name: "HotCorners"

    function test_defaults_when_key_is_absent() {
        var c = Corners.resolve(undefined);
        compare(c.enabled, true);
        compare(c.size, 4);
        compare(c.delayMs, 400);
        compare(c.corners.topLeft, "none");
        compare(c.corners.topRight, "none");
        compare(c.corners.bottomLeft, "screensaver");
        compare(c.corners.bottomRight, "lock");
        compare(c.warnings.length, 0);
    }

    function test_partial_config_keeps_the_other_defaults() {
        var c = Corners.resolve({ topLeft: "lock" });
        compare(c.corners.topLeft, "lock");
        compare(c.corners.bottomLeft, "screensaver");
        compare(c.corners.bottomRight, "lock");
        compare(c.warnings.length, 0);
    }

    function test_explicit_none_disables_one_corner() {
        var c = Corners.resolve({ bottomRight: "none" });
        compare(c.corners.bottomRight, "none");
        compare(c.corners.bottomLeft, "screensaver");
    }

    function test_unknown_action_warns_and_falls_back_to_none() {
        var c = Corners.resolve({ bottomLeft: "explode" });
        compare(c.corners.bottomLeft, "none");
        compare(c.warnings.length, 1);
        verify(c.warnings[0].indexOf("bottomLeft") >= 0);
    }

    function test_non_string_action_warns_rather_than_throwing() {
        var c = Corners.resolve({ topRight: 7 });
        compare(c.corners.topRight, "none");
        compare(c.warnings.length, 1);
    }

    function test_size_and_delay_are_clamped() {
        var big = Corners.resolve({ size: 4000, delayMs: 999999 });
        compare(big.size, 64);
        compare(big.delayMs, 10000);
        var small = Corners.resolve({ size: 0, delayMs: -50 });
        compare(small.size, 1);
        compare(small.delayMs, 0);
        compare(big.warnings.length, 0);
    }

    function test_non_numeric_size_warns_and_keeps_the_default() {
        var c = Corners.resolve({ size: "wide" });
        compare(c.size, 4);
        compare(c.warnings.length, 1);
    }

    function test_edges_are_the_corner_two_and_only_those() {
        var bl = Corners.edges("bottomLeft");
        compare(bl.bottom, true);
        compare(bl.left, true);
        compare(bl.top, false);
        compare(bl.right, false);
        var tr = Corners.edges("topRight");
        compare(tr.top, true);
        compare(tr.right, true);
        compare(tr.bottom, false);
        compare(tr.left, false);
    }

    function test_windows_covers_every_screen_and_skips_none() {
        var c = Corners.resolve(undefined);
        var wins = Corners.windows(c, ["HDMI-1", "DP-1"]);
        compare(wins.length, 4);
        compare(wins[0].screen, "HDMI-1");
        compare(wins[0].corner, "bottomLeft");
        compare(wins[0].action, "screensaver");
        compare(wins[1].corner, "bottomRight");
        compare(wins[1].action, "lock");
        compare(wins[2].screen, "DP-1");
        compare(wins[3].screen, "DP-1");
    }

    function test_windows_is_empty_when_disabled() {
        var c = Corners.resolve({ enabled: false });
        compare(Corners.windows(c, ["HDMI-1"]).length, 0);
    }

    function test_windows_is_empty_when_every_corner_is_none() {
        var c = Corners.resolve({ bottomLeft: "none", bottomRight: "none" });
        compare(Corners.windows(c, ["HDMI-1"]).length, 0);
    }
}
