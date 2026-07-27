.pragma library

// Pure reducer for niri's EventStream JSON protocol. `reduce(state, event)`
// never mutates `state`; it returns a new state object. Unknown event keys
// are returned unchanged (niri's forward-compat mandate).

function initialState() {
    return {
        workspaces: [],
        windows: [],
        outputs: [],
        focusedWindowId: "",
        focusedWorkspaceId: "",
        focusedOutputName: "",
        overviewOpen: false,
        configLoadFailed: false,
        raw: { workspaces: {}, windows: {} }
    };
}

function normalizeWorkspace(ws) {
    return {
        id: String(ws.id),
        idx: ws.idx,
        name: ws.name ?? "",
        output: ws.output,
        isActive: ws.is_active,
        isFocused: ws.is_focused,
        isUrgent: ws.is_urgent
    };
}

function normalizeWindow(win) {
    return {
        id: String(win.id),
        title: win.title,
        appId: win.app_id ?? "",
        workspaceId: String(win.workspace_id),
        isFocused: win.is_focused,
        isFloating: win.is_floating,
        isUrgent: win.is_urgent
    };
}

function withWorkspaces(state, workspaces) {
    var focused = workspaces.find(function (ws) { return ws.isFocused; });
    return Object.assign({}, state, {
        workspaces: workspaces,
        focusedWorkspaceId: focused ? focused.id : state.focusedWorkspaceId
    });
}

function withWindows(state, windows) {
    var focused = windows.find(function (win) { return win.isFocused; });
    return Object.assign({}, state, {
        windows: windows,
        focusedWindowId: focused ? focused.id : state.focusedWindowId
    });
}

function reduce(state, event) {
    var key = Object.keys(event)[0];
    var payload = event[key];

    switch (key) {
    case "WorkspacesChanged":
        return withWorkspaces(state, payload.workspaces.map(normalizeWorkspace));

    case "WorkspaceActivated": {
        var id = String(payload.id);
        var activated = state.workspaces.find(function (ws) { return ws.id === id; });
        var output = activated ? activated.output : null;
        var focused = payload.focused;
        var workspaces = state.workspaces.map(function (ws) {
            var gotActivated = ws.id === id;
            return Object.assign({}, ws, {
                isActive: ws.output === output ? gotActivated : ws.isActive,
                isFocused: focused ? gotActivated : ws.isFocused
            });
        });
        var next = Object.assign({}, state, { workspaces: workspaces });
        if (focused) next.focusedWorkspaceId = id;
        return next;
    }

    case "WorkspaceUrgencyChanged": {
        var id = String(payload.id);
        return Object.assign({}, state, {
            workspaces: state.workspaces.map(function (ws) {
                return ws.id === id ? Object.assign({}, ws, { isUrgent: payload.urgent }) : ws;
            })
        });
    }

    case "WorkspaceActiveWindowChanged":
        return state;

    case "WindowsChanged":
        return withWindows(state, payload.windows.map(normalizeWindow));

    case "WindowOpenedOrChanged": {
        var win = normalizeWindow(payload.window);
        var found = false;
        var windows = state.windows.map(function (w) {
            if (w.id === win.id) { found = true; return win; }
            return win.isFocused ? Object.assign({}, w, { isFocused: false }) : w;
        });
        if (!found) windows = windows.concat([win]);
        return Object.assign({}, state, {
            windows: windows,
            focusedWindowId: win.isFocused ? win.id : state.focusedWindowId
        });
    }

    case "WindowClosed": {
        var id = String(payload.id);
        return Object.assign({}, state, {
            windows: state.windows.filter(function (w) { return w.id !== id; }),
            focusedWindowId: state.focusedWindowId === id ? "" : state.focusedWindowId
        });
    }

    case "WindowFocusChanged": {
        var id = payload.id === null || payload.id === undefined ? "" : String(payload.id);
        return Object.assign({}, state, {
            windows: state.windows.map(function (w) {
                return Object.assign({}, w, { isFocused: w.id === id });
            }),
            focusedWindowId: id
        });
    }

    case "WindowUrgencyChanged": {
        var id = String(payload.id);
        return Object.assign({}, state, {
            windows: state.windows.map(function (w) {
                return w.id === id ? Object.assign({}, w, { isUrgent: payload.urgent }) : w;
            })
        });
    }

    case "OverviewOpenedOrClosed":
        return Object.assign({}, state, { overviewOpen: payload.is_open });

    case "ConfigLoaded":
        return Object.assign({}, state, { configLoadFailed: payload.failed });

    default:
        return state;
    }
}
