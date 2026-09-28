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

    function rwin(id, workspaceId, x, y, flags) {
        flags = flags || {};
        return {
            id: id,
            workspaceId: workspaceId,
            appId: flags.appId || "",
            title: "t-" + id,
            pid: 0,
            isFocused: flags.focused === true,
            isUrgent: flags.urgent === true,
            isFloating: flags.floating === true,
            rect: x === null ? null : { x: x, y: y, width: 100, height: 100 }
        };
    }

    function test_persistent_fills_missing_slots_as_placeholders() {
        var model = WorkspacesModel.visibleModel([
            ws("7", 2, "eDP-1", { active: true, focused: true })
        ], [], "eDP-1", 3);
        compare(model.map(function (w) { return w.idx; }).join(","), "1,2,3");
        compare(model[0].id, "");
        compare(model[0].placeholder, true);
        compare(model[1].id, "7");
        compare(model[1].placeholder, undefined);
    }

    function test_persistent_keeps_existing_empty_workspace() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1", { active: true, focused: true }),
            ws("2", 2, "eDP-1"),
            ws("4", 4, "eDP-1")
        ], [], "eDP-1", 2);
        compare(ids(model), "1,2");
    }

    function test_persistent_leaves_another_outputs_workspace_alone() {
        var model = WorkspacesModel.visibleModel([
            ws("1", 1, "eDP-1", { active: true, focused: true }),
            ws("2", 2, "HDMI-A-1", { active: true })
        ], [], "eDP-1", 2);
        compare(ids(model), "1");
    }

    function test_slot_windows_in_screen_order() {
        var list = WorkspacesModel.slotWindows([
            rwin("b", "1", 500, 0),
            rwin("x", "2", 0, 0),
            rwin("c", "1", 0, 500),
            rwin("a", "1", 0, 0),
            rwin("n", "1", null)
        ], "1", 8);
        compare(list.windows.map(function (w) { return w.id; }).join(","), "a,c,b,n");
        compare(list.overflow, 0);
    }

    function test_slot_windows_cap_keeps_focused() {
        var list = WorkspacesModel.slotWindows([
            rwin("a", "1", 0, 0),
            rwin("b", "1", 100, 0),
            rwin("c", "1", 200, 0),
            rwin("d", "1", 300, 0, { focused: true })
        ], "1", 2);
        compare(list.windows.map(function (w) { return w.id; }).join(","), "a,d");
        compare(list.overflow, 2);
    }

    function test_slot_windows_drop_title_and_rect() {
        var list = WorkspacesModel.slotWindows([rwin("a", "1", 0, 0, { appId: "foot" })], "1", 8);
        compare(list.windows[0].appId, "foot");
        compare(list.windows[0].title, undefined);
        compare(list.windows[0].rect, undefined);
    }

    function test_placeholder_slot_has_no_windows() {
        var list = WorkspacesModel.slotWindows([rwin("a", "", 0, 0)], "", 8);
        compare(list.windows.length, 0);
    }

    function test_slots_label_urgent_and_current() {
        var named = ws("3", 3, "eDP-1");
        named.name = "web";
        var model = WorkspacesModel.slots([
            ws("1", 1, "eDP-1", { active: true, focused: true }),
            named
        ], [rwin("a", "3", 0, 0, { urgent: true })], "eDP-1", { persistent: 0, maxIcons: 8 });
        compare(model.length, 2);
        compare(model[0].label, "1");
        compare(model[0].current, true);
        compare(model[0].isUrgent, false);
        compare(model[1].label, "3");
        compare(model[1].name, "web");
        compare(model[1].current, false);
        compare(model[1].isUrgent, true);
        compare(model[1].windows.length, 1);
    }

    function test_shows_apps_modes() {
        compare(WorkspacesModel.showsApps("all", false, false), true);
        compare(WorkspacesModel.showsApps("active", false, true), false);
        compare(WorkspacesModel.showsApps("active", true, false), true);
        compare(WorkspacesModel.showsApps("hover", false, true), true);
        compare(WorkspacesModel.showsApps("hover", false, false), false);
        compare(WorkspacesModel.showsApps("bogus", true, false), true);
    }

    function test_step_index_wraps() {
        compare(WorkspacesModel.stepIndex(3, 2, 1), 0);
        compare(WorkspacesModel.stepIndex(3, 0, -1), 2);
        compare(WorkspacesModel.stepIndex(3, -1, 1), 0);
        compare(WorkspacesModel.stepIndex(0, 0, 1), -1);
    }

    function test_preview_layout_scales_and_clamps() {
        var area = { x: 1000, y: 0, width: 1000, height: 500 };
        var placed = WorkspacesModel.previewLayout([
            { id: "a", rect: { x: 1000, y: 0, width: 500, height: 500 } },
            { id: "b", rect: { x: 1900, y: 400, width: 500, height: 500 }, isFloating: true }
        ], area, 200, 100, 4);
        compare(placed.length, 2);
        compare(placed[0].id, "a");
        compare(placed[0].x, 0);
        compare(placed[0].width, 100);
        compare(placed[0].height, 100);
        compare(placed[1].id, "b");
        compare(placed[1].x, 180);
        compare(placed[1].y, 80);
        compare(placed[1].width, 20);
        compare(placed[1].height, 20);
    }

    function test_preview_layout_floating_draws_last() {
        var area = { x: 0, y: 0, width: 100, height: 100 };
        var placed = WorkspacesModel.previewLayout([
            { id: "f", rect: { x: 0, y: 0, width: 10, height: 10 }, isFloating: true },
            { id: "t", rect: { x: 0, y: 0, width: 100, height: 100 } }
        ], area, 100, 100, 4);
        compare(placed.map(function (p) { return p.id; }).join(","), "t,f");
    }

    function test_preview_layout_grid_without_rects() {
        var placed = WorkspacesModel.previewLayout([
            { id: "a", rect: null }, { id: "b", rect: null }, { id: "c", rect: null }
        ], { x: 0, y: 0, width: 100, height: 100 }, 200, 100, 4);
        compare(placed.length, 3);
        compare(placed[0].width, 100);
        compare(placed[0].height, 50);
        compare(placed[2].x, 0);
        compare(placed[2].y, 50);
    }
}
