.pragma library

// Where a window goes when it is parked out of view.
//
// Hyprland has a special workspace for this; niri has no hide primitive at
// all (no minimize, no scratchpad, nothing in `niri msg action`), so the
// only way out of view is another workspace. This picks which one, and it
// is pure so the choice is testable without a compositor
// (tests/tst_compositor_park.qml).
//
// Preference order, all restricted to the focused output so the parked
// window never lands on a screen the user is not looking at:
//   1. the highest-index workspace holding nothing else — on niri that is
//      the trailing empty workspace every output always carries, so parking
//      normally costs no workspace anyone was using;
//   2. failing that, the highest-index workspace that is not the focused
//      one, which parks on top of other windows but still gets it out of
//      the way;
//   3. "" — nowhere to park. One output with exactly one workspace, which
//      niri's always-trailing-empty rule means is effectively never, and
//      the null backend, which parks nothing anyway.
function parkTarget(workspaces, windows, focusedWorkspaceId, focusedOutputName, windowId) {
    var all = workspaces || [];
    var candidates = all.filter(function (w) {
        if (!w || w.id === focusedWorkspaceId)
            return false;
        // An output name this shell has not resolved yet is not a reason to
        // refuse to park: with nothing to filter on, every workspace is a
        // candidate.
        return focusedOutputName === "" || w.output === focusedOutputName;
    });
    if (candidates.length === 0)
        return "";

    candidates.sort(function (a, b) { return (a.idx || 0) - (b.idx || 0); });

    var occupied = {};
    var wins = windows || [];
    for (var i = 0; i < wins.length; i++) {
        // The window being parked does not count against its own
        // destination: parking twice in a row must pick the same workspace,
        // not walk the console one workspace further out every time.
        if (!wins[i] || wins[i].id === windowId)
            continue;
        occupied[wins[i].workspaceId] = true;
    }

    for (var j = candidates.length - 1; j >= 0; j--) {
        if (!occupied[candidates[j].id])
            return candidates[j].id;
    }
    return candidates[candidates.length - 1].id;
}
