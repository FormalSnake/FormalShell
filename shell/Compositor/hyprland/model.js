.pragma library

// Pure mapping from Quickshell's Hyprland workspace objects onto the
// BackendBase `workspaces` contract, kept out of the QML binding so the
// special-workspace rule is testable without a compositor
// (tests/tst_hyprland_workspaces.qml).
//
// Special workspaces are dropped. Hyprland gives them a negative id and a
// `special:<name>` name because they are overlays, not places the user
// switches between, and the quake console lives on one permanently (see
// HyprlandBackend's parking section), which otherwise stands a
// `special:formalshell-console` cell in the bar's workspace strip forever.
// Nothing downstream needs them: parking works off window ids and the
// monitor's own `specialWorkspace` field, never this list.
function mapWorkspaces(values) {
    var list = values || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (!w || w.id < 0)
            continue;
        out.push({
            id: String(w.id),
            idx: w.id,
            name: w.name ?? "",
            output: w.monitor ? w.monitor.name : "",
            isActive: w.active,
            isFocused: w.focused,
            isUrgent: w.urgent
        });
    }
    return out;
}
