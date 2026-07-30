.pragma library

// Pure model for the bar's workspace cells (M13 Task 1): which workspaces
// render and in what order. No Quickshell access, so it's testable head-on.
// A workspace renders only if it holds at least one window or is
// active/focused — niri declares every persistent named workspace on every
// output all the time, so without the occupancy filter a nine-workspace
// config shows nine cells with two windows open. Occupancy is counted from
// the windows list by workspace id because the backends' workspace payloads
// carry no occupancy field of their own (niri-ipc's Workspace has only
// active_window_id, which the reducer's ignored WorkspaceActiveWindowChanged
// event would have to maintain; counting windows works identically for
// Hyprland). Order is the backend's own per-output ordinal `idx` (niri's
// Workspace.idx, Hyprland's numeric id) — ids stay opaque strings, never
// parsed. Workspaces on `outputName` win; when none match (compositor output
// name vs Quickshell screen name mismatch) every workspace is considered,
// grouped by output name so the fallback stays deterministic.

function visibleModel(workspaces, windows, outputName) {
    var pool = workspaces.filter(function (ws) { return ws.output === outputName; });
    if (pool.length === 0)
        pool = workspaces.slice();

    var occupied = {};
    for (var i = 0; i < windows.length; i++)
        occupied[windows[i].workspaceId] = true;

    return pool
        .filter(function (ws) { return occupied[ws.id] === true || ws.isActive || ws.isFocused; })
        .sort(function (a, b) {
            if (a.output !== b.output)
                return a.output < b.output ? -1 : 1;
            return a.idx - b.idx;
        });
}
