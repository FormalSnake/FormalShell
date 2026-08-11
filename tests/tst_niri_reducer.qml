import QtQuick
import QtTest
import "../shell/Compositor/niri/reducer.js" as R

TestCase {
    name: "NiriReducer"

    function test_hydrate_workspaces() {
        var s = R.reduce(R.initialState(), { WorkspacesChanged: { workspaces: [
            { id: 3, idx: 1, name: null, output: "eDP-1", is_urgent: false, is_active: true, is_focused: true, active_window_id: 7 },
            { id: 9, idx: 2, name: "mail", output: "eDP-1", is_urgent: false, is_active: false, is_focused: false, active_window_id: null }
        ]}});
        compare(s.workspaces.length, 2);
        compare(s.workspaces[0].id, "3");           // opaque string
        compare(s.workspaces[1].name, "mail");
        compare(s.focusedWorkspaceId, "3");
    }

    function test_window_focus_change() {
        var s = R.reduce(R.initialState(), { WindowsChanged: { windows: [
            { id: 7, title: "ghostty", app_id: "com.mitchellh.ghostty", pid: 1, workspace_id: 3, is_focused: true, is_floating: false, is_urgent: false }
        ]}});
        s = R.reduce(s, { WindowFocusChanged: { id: null } });
        compare(s.focusedWindowId, "");
        compare(s.windows[0].isFocused, false);
    }

    function test_window_closed() {
        var s = R.reduce(R.initialState(), { WindowsChanged: { windows: [
            { id: 7, title: "a", app_id: "a", pid: 1, workspace_id: 3, is_focused: false, is_floating: false, is_urgent: false },
            { id: 8, title: "b", app_id: "b", pid: 1, workspace_id: 3, is_focused: false, is_floating: false, is_urgent: false }
        ]}});
        s = R.reduce(s, { WindowClosed: { id: 7 } });
        compare(s.windows.length, 1);
        compare(s.windows[0].id, "8");
    }

    function test_workspace_activated_updates_focus_and_active() {
        var s = R.reduce(R.initialState(), { WorkspacesChanged: { workspaces: [
            { id: 3, idx: 1, name: null, output: "eDP-1", is_urgent: false, is_active: true, is_focused: true, active_window_id: 7 },
            { id: 9, idx: 2, name: "mail", output: "eDP-1", is_urgent: false, is_active: false, is_focused: false, active_window_id: null }
        ]}});
        s = R.reduce(s, { WorkspaceActivated: { id: 9, focused: true } });
        compare(s.workspaces[0].isActive, false);
        compare(s.workspaces[0].isFocused, false);
        compare(s.workspaces[1].isActive, true);
        compare(s.workspaces[1].isFocused, true);
        compare(s.focusedWorkspaceId, "9");
    }

    function test_workspace_activated_without_focus_leaves_is_focused() {
        var s = R.reduce(R.initialState(), { WorkspacesChanged: { workspaces: [
            { id: 3, idx: 1, name: null, output: "eDP-1", is_urgent: false, is_active: true, is_focused: true, active_window_id: 7 },
            { id: 9, idx: 2, name: "mail", output: "DP-2", is_urgent: false, is_active: false, is_focused: false, active_window_id: null }
        ]}});
        s = R.reduce(s, { WorkspaceActivated: { id: 9, focused: false } });
        compare(s.workspaces[0].isFocused, true);
        compare(s.workspaces[1].isActive, true);
        compare(s.workspaces[1].isFocused, false);
        compare(s.focusedWorkspaceId, "3");
    }

    function test_overview_opened_or_closed() {
        var s = R.reduce(R.initialState(), { OverviewOpenedOrClosed: { is_open: true } });
        compare(s.overviewOpen, true);
    }

    function test_unknown_event_ignored() {
        var s0 = R.initialState();
        var s1 = R.reduce(s0, { SomeFutureEvent: { whatever: 1 } });
        compare(JSON.stringify(s1), JSON.stringify(s0));
    }

    function test_reduce_is_pure() {
        var s0 = R.initialState();
        R.reduce(s0, { WorkspacesChanged: { workspaces: [ { id: 1, idx: 1, name: null, output: "x", is_urgent: false, is_active: true, is_focused: true, active_window_id: null } ] } });
        compare(s0.workspaces.length, 0);
    }

    // --- window geometry (M22 Task 4) ---

    function _stateWithLayout(layout) {
        return R.reduce(R.reduce(R.initialState(), { WorkspacesChanged: { workspaces: [
            { id: 3, idx: 1, name: null, output: "DP-2", is_urgent: false, is_active: true, is_focused: true, active_window_id: 7 }
        ]}}), { WindowsChanged: { windows: [
            { id: 7, title: "a", app_id: "a", pid: 1, workspace_id: 3, is_focused: true, is_floating: false, is_urgent: false, layout: layout }
        ]}});
    }

    readonly property var outputs: [ { name: "DP-2", x: 1920, y: 0, width: 2560, height: 1440 } ]

    function test_window_rect_offsets_by_output_origin() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: [10, 20], window_size: [800, 600] });
        var w = R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0];
        compare(w.rect.x, 1930);
        compare(w.rect.y, 20);
        compare(w.rect.width, 800);
        compare(w.rect.height, 600);
    }

    function test_window_offset_in_tile_is_applied() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: [10, 20], tile_size: [820, 620], window_size: [800, 600], window_offset_in_tile: [10, 10] });
        var w = R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0];
        compare(w.rect.x, 1940);
        compare(w.rect.y, 30);
        compare(w.rect.width, 800);
    }

    function test_tile_size_is_the_fallback_when_window_size_absent() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: [0, 0], tile_size: [640, 480] });
        var w = R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0];
        compare(w.rect.width, 640);
        compare(w.rect.height, 480);
    }

    // A window scrolled out of the view has no position at all. It must stay
    // null: a zeroed box would be a real rectangle at the origin, which the
    // capture picker would highlight and crop to.
    function test_offscreen_window_has_null_rect() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: null, window_size: [800, 600] });
        compare(s.windows[0].viewRect, null);
        compare(R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0].rect, null);
    }

    function test_window_without_layout_has_null_rect() {
        var s = _stateWithLayout(undefined);
        compare(R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0].rect, null);
    }

    // The dominant niri case, and the reason the capture picker cannot hint
    // window rectangles on this backend: a TILED window reports its position
    // only as a 1-based (column, row) index, never pixels
    // (src/layout/scrolling.rs:2426 inheriting tile.rs:869's None). Asserted
    // so a future niri that starts filling the field in fails here loudly
    // rather than silently changing what the picker can do.
    function test_tiled_window_has_no_rect() {
        var s = _stateWithLayout({ pos_in_scrolling_layout: [1, 1], tile_size: [1280, 1400], window_size: [1280, 1376], tile_pos_in_workspace_view: null });
        compare(s.windows[0].viewRect, null);
        compare(R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0].rect, null);
    }

    function test_floating_window_does_have_a_rect() {
        var s = _stateWithLayout({ pos_in_scrolling_layout: null, tile_pos_in_workspace_view: [100, 50], window_size: [640, 480] });
        compare(R.withAbsoluteRects(s.windows, s.workspaces, outputs)[0].rect.x, 2020);
    }

    // Outputs arrive from a separate request than the event stream, so there
    // is a real window where windows are known and outputs are not.
    function test_rect_is_null_until_outputs_land() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: [10, 20], window_size: [800, 600] });
        compare(R.withAbsoluteRects(s.windows, s.workspaces, [])[0].rect, null);
    }

    function test_absolute_rects_do_not_mutate_input() {
        var s = _stateWithLayout({ tile_pos_in_workspace_view: [10, 20], window_size: [800, 600] });
        R.withAbsoluteRects(s.windows, s.workspaces, outputs);
        compare(s.windows[0].rect, undefined);
    }
}
