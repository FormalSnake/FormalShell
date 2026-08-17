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

// niri reports a window's box relative to its WORKSPACE VIEW, not to the
// output. `window_size` is the window proper; `tile_size` is the tile around
// it, and is the fallback when only the tile was reported.
// `window_offset_in_tile` positions the window inside that tile.
//
// ⚠️ On niri v26.04 only FLOATING windows carry a position. Verified against
// the pinned source: `Tile::ipc_layout_template` hardcodes
// `tile_pos_in_workspace_view: None` (src/layout/tile.rs:869), floating.rs
// fills it in (:336), and the scrolling (tiled) layout overrides only
// `pos_in_scrolling_layout` (src/layout/scrolling.rs:2426), inheriting the
// None. `pos_in_scrolling_layout` is a 1-based (column, row) index pair, not
// pixels, so it cannot be converted into one.
//
// So a tiled niri window — which is nearly all of them — has NO rectangle,
// and this returns null for it. That is the compositor's limit, not a gap
// here: anything wanting to capture a niri window works by window id through
// the `ScreenshotWindow` action (niri crops server-side), never by rect.
function windowViewRect(layout) {
    if (!layout)
        return null;
    var pos = layout.tile_pos_in_workspace_view;
    var size = layout.window_size || layout.tile_size;
    if (!Array.isArray(pos) || !Array.isArray(size) || !(size[0] > 0) || !(size[1] > 0))
        return null;
    var offset = Array.isArray(layout.window_offset_in_tile) ? layout.window_offset_in_tile : [0, 0];
    return {
        x: pos[0] + offset[0],
        y: pos[1] + offset[1],
        width: size[0],
        height: size[1]
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
        isUrgent: win.is_urgent,
        viewRect: windowViewRect(win.layout)
    };
}

// View-relative boxes -> the absolute logical coordinates BackendBase's `rect`
// contract promises, by way of each window's workspace and that workspace's
// output origin. Outputs arrive from a separate request than the event stream
// (see NiriBackend), so until they land every `rect` is honestly null rather
// than a box at the origin.
function withAbsoluteRects(windows, workspaces, outputs) {
    var outputByName = {};
    (outputs || []).forEach(function (out) { outputByName[out.name] = out; });

    var outputByWorkspace = {};
    (workspaces || []).forEach(function (ws) { outputByWorkspace[ws.id] = ws.output; });

    return (windows || []).map(function (win) {
        var out = outputByName[outputByWorkspace[win.workspaceId]];
        if (!win.viewRect || !out)
            return Object.assign({}, win, { rect: null });
        return Object.assign({}, win, {
            rect: {
                x: out.x + win.viewRect.x,
                y: out.y + win.viewRect.y,
                width: win.viewRect.width,
                height: win.viewRect.height
            }
        });
    });
}

// niri's event stream has no focused-output event at all (niri-ipc's `Event`
// enum), and the Outputs request that does enumerate outputs carries no focus
// flag. The focused workspace's own `output` is therefore the only report of
// which output is active, and every surface that opens on the focused screen
// resolves through it — a focusedOutputName left empty here silently sends all
// of them to Quickshell.screens[0].
function withWorkspaces(state, workspaces) {
    var focused = workspaces.find(function (ws) { return ws.isFocused; });
    return Object.assign({}, state, {
        workspaces: workspaces,
        focusedWorkspaceId: focused ? focused.id : state.focusedWorkspaceId,
        focusedOutputName: focused && focused.output ? focused.output : state.focusedOutputName
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
        if (focused) {
            next.focusedWorkspaceId = id;
            // Moving focus across outputs arrives as nothing but this event,
            // so the activated workspace's output is where focus now is. An
            // activation for a workspace this state has never seen leaves the
            // last known output rather than blanking it.
            if (output) next.focusedOutputName = output;
        }
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
