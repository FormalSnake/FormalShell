import Quickshell.Io

import qs.Compositor

// `qs ipc call debug dump` — the scripted-verification hook every later
// task uses to assert on live compositor state from outside the process.
IpcHandler {
    target: "debug"

    // CompositorService is a lazily-instantiated singleton: nothing constructs
    // it (or connects its backend) until something reads one of its
    // properties. Touch it here, at DebugIpc's own construction, so the
    // backend is already connected and streaming by the time anything calls
    // dump() — otherwise the very first call would race the connection.
    readonly property bool _warmCompositor: CompositorService.available

    function dump(): string {
        return JSON.stringify({
            compositor: CompositorService.compositor,
            available: CompositorService.available,
            workspaces: CompositorService.workspaces,
            windows: CompositorService.windows,
            focusedWindowId: CompositorService.focusedWindowId,
            focusedWorkspaceId: CompositorService.focusedWorkspaceId
        });
    }
}
