import Quickshell.Io

import qs.Compositor
import qs.Core as Core

// `qs ipc call debug dump` — the scripted-verification hook every later
// task uses to assert on live compositor state from outside the process.
IpcHandler {
    target: "debug"

    // Set from shell.qml — the menu instance to query() against. Menu.qml
    // has no singleton of its own (only one instance, opened on demand), so
    // DebugIpc can't reach it any other way.
    property var menu: null

    // CompositorService is a lazily-instantiated singleton: nothing constructs
    // it (or connects its backend) until something reads one of its
    // properties. Touch it here, at DebugIpc's own construction, so the
    // backend is already connected and streaming by the time anything calls
    // dump() — otherwise the very first call would race the connection.
    readonly property bool _warmCompositor: CompositorService.available

    // Same lazy-singleton hazard for Config: its FileView load is async, so
    // reading Core.Config.settings for the first time inside dump() itself
    // would race the load and observe the {} initial value. Touch it here
    // instead, at construction, well before any call reaches dump().
    readonly property bool _warmConfig: Core.Config.settings !== undefined

    function dump(): string {
        return JSON.stringify({
            compositor: CompositorService.compositor,
            available: CompositorService.available,
            workspaces: CompositorService.workspaces,
            windows: CompositorService.windows,
            focusedWindowId: CompositorService.focusedWindowId,
            focusedWorkspaceId: CompositorService.focusedWorkspaceId,
            configLoaded: Core.Config.settings
        });
    }

    // `qs ipc call debug query "<text>"` — ranks a query against the live
    // menu tree without opening the surface (no keyboard injection in a
    // nested test session); verifies the apps provider + fuzzy filtering.
    function query(q: string): string {
        return JSON.stringify(menu ? menu.query(q) : []);
    }
}
