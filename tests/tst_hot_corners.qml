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

    // The launcher action strings (M45 D5): the same two forms Menu.qml's own
    // _runAction resolves, kept verbatim so HotCorners hands it the string it
    // was configured with.
    function test_an_ipc_action_string_is_kept_verbatim() {
        var c = Corners.resolve({ topLeft: "@ipc:notifications.showHistory" });
        compare(c.corners.topLeft, "@ipc:notifications.showHistory");
        compare(c.warnings.length, 0);
        verify(Corners.isLauncherAction("@ipc:notifications.showHistory"));
        verify(Corners.isLauncherAction("@ipc:clipboard.copy:3"));
    }

    function test_a_command_line_is_kept_verbatim() {
        var c = Corners.resolve({ topRight: "hyprctl dispatch workspace 1" });
        compare(c.corners.topRight, "hyprctl dispatch workspace 1");
        compare(c.warnings.length, 0);
        verify(Corners.isLauncherAction("/usr/bin/hyprlock"));
    }

    function test_a_custom_action_reaches_the_window_list() {
        var c = Corners.resolve({ bottomLeft: "@ipc:theme.toggleMode" });
        var wins = Corners.windows(c, ["HDMI-1"]);
        compare(wins.length, 2);
        compare(wins[0].action, "@ipc:theme.toggleMode");
    }

    // The built-ins are the surface's own, never the launcher's: routing
    // "lock" through the resolver would spawn a shell command called lock.
    function test_the_built_in_names_are_not_launcher_actions() {
        verify(!Corners.isLauncherAction("lock"));
        verify(!Corners.isLauncherAction("screensaver"));
        verify(!Corners.isLauncherAction("none"));
    }

    // A malformed one is a typo like any other, so it takes the same path.
    function test_a_malformed_ipc_string_is_refused() {
        verify(!Corners.isLauncherAction("@ipc:showHistory"));
        var c = Corners.resolve({ topLeft: "@ipc:showHistory" });
        compare(c.corners.topLeft, "none");
        compare(c.warnings.length, 1);
    }

    function test_unknown_action_warns_and_falls_back_to_none() {
        var c = Corners.resolve({ bottomLeft: "explode" });
        compare(c.corners.bottomLeft, "none");
        compare(c.warnings.length, 1);
        verify(c.warnings[0].indexOf("bottomLeft") >= 0);
        verify(!Corners.isLauncherAction("explode"));
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
