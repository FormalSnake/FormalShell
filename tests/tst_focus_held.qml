import QtQuick
import QtTest
import "../shell/Compositor/focus.js" as Focus

TestCase {
    name: "FocusHeld"

    function win(id, workspaceId) {
        return { id: id, workspaceId: workspaceId, appId: "app", title: "t" };
    }

    readonly property var windows: [win("1", "ws1"), win("2", "ws2")]

    function test_live_focus_wins_over_the_remembered_id() {
        compare(Focus.held("2", "1", windows, "ws2"), "2");
    }

    function test_focus_is_held_while_the_compositor_reports_none() {
        compare(Focus.held("", "1", windows, "ws1"), "1");
    }

    function test_nothing_remembered_yet_stays_empty() {
        compare(Focus.held("", "", windows, "ws1"), "");
    }

    function test_remembered_window_that_closed_is_dropped() {
        compare(Focus.held("", "9", windows, "ws1"), "");
    }

    function test_remembered_window_on_another_workspace_is_dropped() {
        compare(Focus.held("", "1", windows, "ws2"), "");
    }

    function test_unknown_focused_workspace_still_holds() {
        compare(Focus.held("", "1", windows, ""), "1");
    }
}
