import QtQuick
import QtTest
import "../shell/Bar/workspaces.js" as WorkspacesModel

TestCase {
    name: "WorkspacesModel"

    function ws(id, idx, output, flags) {
        flags = flags || {};
        return {
            id: id,
            idx: idx,
            name: "",
            output: output,
            isActive: flags.active === true,
            isFocused: flags.focused === true,
            isUrgent: false
        };
    }

    function win(id, workspaceId) {
        return { id: id, workspaceId: workspaceId };
    }

    function ids(model) {
        return model.map(function (w) { return w.id; }).join(",");
    }

    function test_sorts_by_idx_not_input_order() {
        var model = WorkspacesModel.visibleModel([
            ws("30", 3, "eDP-1"),
            ws("10", 1, "eDP-1"),
            ws("20", 2, "eDP-1")
        ], [win("a", "10"), win("b", "20"), win("c", "30")], "eDP-1");
        compare(ids(model), "10,20,30");
    }

    function test_id_is_never_the_sort_key() {
        // ids are opaque: descending ids with ascending idx must order by idx
        var model = WorkspacesModel.visibleModel([
            ws("9", 2, "eDP-1"),
            ws("100", 1, "eDP-1")
        ], [win("a", "9"), win("b", "100")], "eDP-1");
        compare(ids(model), "100,9");
    }

    function test_hides_empty_inactive_workspaces() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1", { active: true, focused: true }),
            ws("2", 2, "eDP-1"),
            ws("3", 3, "eDP-1"),
            ws("4", 4, "eDP-1")
        ], [win("a", "1"), win("b", "3")], "eDP-1");
        compare(ids(model), "1,3");
    }

    function test_keeps_focused_workspace_without_windows() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1"),
            ws("2", 2, "eDP-1", { active: true, focused: true })
        ], [win("a", "1")], "eDP-1");
        compare(ids(model), "1,2");
    }

    function test_keeps_active_but_unfocused_workspace() {
        // multi-output: active on its output, focus elsewhere
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "HDMI-A-1", { active: true }),
            ws("2", 2, "HDMI-A-1")
        ], [], "HDMI-A-1");
        compare(ids(model), "1");
    }

    function test_filters_to_named_output() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1", { active: true }),
            ws("2", 1, "HDMI-A-1", { active: true })
        ], [], "eDP-1");
        compare(ids(model), "1");
    }

    function test_falls_back_to_all_outputs_when_none_match() {
        var model = WorkspacesModel.visibleModel([
            ws("2", 1, "HDMI-A-1", { active: true }),
            ws("1", 1, "DP-1", { active: true })
        ], [], "winit");
        compare(ids(model), "1,2");
    }

    function test_fallback_groups_by_output_then_idx() {
        var model = WorkspacesModel.visibleModel([
            ws("b2", 2, "HDMI-A-1"),
            ws("a2", 2, "DP-1"),
            ws("b1", 1, "HDMI-A-1"),
            ws("a1", 1, "DP-1")
        ], [win("w", "a1"), win("x", "a2"), win("y", "b1"), win("z", "b2")], "winit");
        compare(ids(model), "a1,a2,b1,b2");
    }

    function test_occupancy_matches_by_workspace_id_string() {
        var model = WorkspacesModel.visibleModel([
            ws("7", 1, "eDP-1", { active: true, focused: true }),
            ws("8", 2, "eDP-1")
        ], [win("a", "8")], "eDP-1");
        compare(ids(model), "7,8");
    }

    function test_empty_windows_shows_only_active() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1", { active: true, focused: true }),
            ws("2", 2, "eDP-1")
        ], [], "eDP-1");
        compare(ids(model), "1");
    }
}
