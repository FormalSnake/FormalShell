import QtQuick
import QtTest
import "../shell/Compositor/park.js" as Park

TestCase {
    name: "CompositorPark"

    function ws(id, idx, output) {
        return { id: id, idx: idx, name: "", output: output || "DP-1" };
    }

    function win(id, workspaceId) {
        return { id: id, workspaceId: workspaceId, appId: "app", title: "t" };
    }

    readonly property var threeWorkspaces: [ws("1", 1), ws("2", 2), ws("3", 3)]

    function test_trailing_empty_workspace_wins() {
        compare(Park.parkTarget(threeWorkspaces, [win("w1", "1"), win("w2", "2")], "1", "DP-1", "w1"), "3");
    }

    function test_focused_workspace_is_never_the_target() {
        compare(Park.parkTarget([ws("1", 1), ws("2", 2)], [], "2", "DP-1", "w1"), "1");
    }

    function test_console_does_not_count_against_its_own_destination() {
        // Parked on 3 already: parking again has to pick 3 again rather than
        // walking one workspace further out on every toggle.
        compare(Park.parkTarget(threeWorkspaces, [win("w1", "3"), win("w2", "2")], "1", "DP-1", "w1"), "3");
    }

    function test_other_outputs_are_not_candidates() {
        var mixed = [ws("1", 1, "DP-1"), ws("2", 2, "HDMI-A-1"), ws("3", 3, "HDMI-A-1")];
        compare(Park.parkTarget(mixed, [], "1", "DP-1", "w1"), "");
    }

    function test_unresolved_output_name_still_parks() {
        compare(Park.parkTarget([ws("1", 1, "DP-1"), ws("2", 2, "HDMI-A-1")], [], "1", "", "w1"), "2");
    }

    function test_every_candidate_occupied_still_parks_on_the_last() {
        compare(Park.parkTarget(threeWorkspaces, [win("w2", "2"), win("w3", "3")], "1", "DP-1", "w1"), "3");
    }

    function test_single_workspace_has_nowhere_to_park() {
        compare(Park.parkTarget([ws("1", 1)], [], "1", "DP-1", "w1"), "");
    }

    function test_missing_models_do_not_throw() {
        compare(Park.parkTarget(undefined, undefined, "1", "DP-1", "w1"), "");
    }
}
