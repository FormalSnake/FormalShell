.pragma library

// Pure model for the bar's workspace cells (M13 Task 1): which workspaces
// render and in what order. No Quickshell access, so it's testable head-on.
// A workspace renders only if it holds at least one window or is
// active/focused: a compositor that declares persistent workspaces up front
// would otherwise show nine cells with two windows open. Occupancy is counted
// from the windows list by workspace id because the backend's workspace
// payload carries no occupancy field of its own. Order is the backend's own
// per-output ordinal `idx` (Hyprland's numeric id), ids stay opaque strings,
// never parsed. Workspaces on `outputName` win; when none match (compositor output
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
