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
}
