.pragma library

// Which window the bar treats as "the app you are in". Pure, so it's
// testable head-on (tests/tst_focus_held.qml).
//
// Both compositors drop their focused window the moment one of the shell's
// own layer surfaces takes keyboard focus, so opening any FormalShell panel
// emptied the bar's active-window cell and reflowed the left region — the
// app appeared to switch when nothing had. Holding the last focused window
// across that gap fixes it without lying anywhere else:
// CompositorService.focusedWindowId stays the compositor's literal answer
// for every other consumer.
//
// The hold is bounded by the focused workspace rather than by knowing which
// surface took focus (the shell has no cross-surface focus registry, and
// neither compositor reports one). A remembered window that has closed, or
// that sits on a workspace you have since left, is dropped — so an empty
// workspace still reads as empty instead of as the last app you used, while
// a panel opening over an app holds that app.
function held(focusedWindowId, rememberedId, windows, focusedWorkspaceId) {
    if (focusedWindowId !== "")
        return focusedWindowId;
    if (!rememberedId)
        return "";
    for (var i = 0; i < windows.length; i++) {
        var win = windows[i];
        if (win.id !== rememberedId)
            continue;
        if (focusedWorkspaceId !== "" && win.workspaceId !== focusedWorkspaceId)
            return "";
        return rememberedId;
    }
    return "";
}
