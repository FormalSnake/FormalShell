import Quickshell.Io

import qs.Compositor
import qs.Core as Core
import qs.Services

// `qs ipc call debug dump`, the scripted-verification hook every later
// task uses to assert on live compositor state from outside the process.
IpcHandler {
    id: root
    target: "debug"

    // Set from shell.qml, the menu instance to query() against. Menu.qml
    // has no singleton of its own (only one instance, opened on demand), so
    // DebugIpc can't reach it any other way.
    property var menu: null

    // CompositorService is a lazily-instantiated singleton: nothing constructs
    // it (or connects its backend) until something reads one of its
    // properties. Touch it here, at DebugIpc's own construction, so the
    // backend is already connected and streaming by the time anything calls
    // dump(), otherwise the very first call would race the connection.
    readonly property bool _warmCompositor: CompositorService.available

    // Same lazy-singleton hazard for Config: its FileView load is async, so
    // reading Core.Config.settings for the first time inside dump() itself
    // would race the load and observe the {} initial value. Touch it here
    // instead, at construction, well before any call reaches dump().
    readonly property bool _warmConfig: Core.Config.settings !== undefined

    // Same lazy-singleton hazard again: AudioService's PwObjectTracker only
    // binds the default sink once something reads AudioService.available,
    // constructing the singleton. Touch it here so the very first dump()
    // already sees bound (valid) volume/muted values, not the unbound 0/false
    // fallback.
    readonly property bool _warmAudio: AudioService.available !== undefined

    // Same lazy-singleton hazard again: BrightnessService's device query is
    // an async Process spawned from Component.onCompleted, which doesn't run
    // until something constructs the singleton. Touch it here so the
    // brightnessctl round-trip has the whole shell-startup-to-first-IPC-call
    // window to land before dump() reads it, instead of racing it.
    readonly property bool _warmBrightness: BrightnessService.available !== undefined

    function dump(): string {
        return JSON.stringify({
            compositor: CompositorService.compositor,
            available: CompositorService.available,
            workspaces: CompositorService.workspaces,
            windows: CompositorService.windows,
            focusedWindowId: CompositorService.focusedWindowId,
            heldFocusedWindowId: CompositorService.heldFocusedWindowId,
            focusedWorkspaceId: CompositorService.focusedWorkspaceId,
            configLoaded: Core.Config.settings,
            audio: {
                volume: AudioService.volume,
                muted: AudioService.muted,
                available: AudioService.available
            },
            brightness: {
                available: BrightnessService.available,
                percent: BrightnessService.percent
            },
            bar: root._bars(),
            join: root._join(),
            // The chrome numbers a leg would otherwise have to restate: the
            // bar's gap is the joined card's rect plus a `radiusXl` fillet at
            // either end, and a leg that hardcoded 14 would go quietly wrong
            // under `theme.radius` or the retro preset.
            theme: {
                radius: Core.Theme.radius,
                radiusXl: Core.Theme.radiusXl,
                borderWidth: Core.Theme.borderWidth,
                barPosition: Core.Theme.barPosition
            }
        });
    }

    // Every mapped strip and the two segments of its inward line (M54 D6):
    // the gap a joined card opens is the shell's own number, so a rig leg
    // asserts on it instead of measuring pixels through a screenshot.
    function _bars() {
        var bars = Core.PanelRegistry.bars;
        var out = [];
        for (var i = 0; i < bars.length; i++) {
            var bar = bars[i];
            out.push({
                screen: bar.modelData ? bar.modelData.name : "",
                edge: bar._position,
                line: bar.lineRects()
            });
        }
        return out;
    }

    function _join() {
        var j = Core.PanelRegistry.join;
        return j ? { edge: j.edge, x: j.x, width: j.width, screen: j.screen } : null;
    }

    // `qs ipc call debug join <edge> <x> <width>`: publishes a join so the
    // bar's gap and Components/Shoulders.qml can be driven headlessly. No
    // surface consumes either until M54 Task 3, so without this route the
    // join could not be seen at all. `joinPreview` below is what draws the
    // card; this handler only ever publishes the rect.
    //
    // A second verb rather than `join clear`, because quickshell dispatches
    // IPC on exact arity (BarIpc.qml's header carries the finding), so one
    // name cannot answer both shapes.
    property var debugJoin: null

    function join(edge: string, x: int, width: int): string {
        if (["top", "bottom", "left", "right"].indexOf(edge) < 0)
            return "error: unknown edge '" + edge + "' (top|bottom|left|right)";
        if (width <= 0)
            return "error: width must be positive";
        var bars = Core.PanelRegistry.bars;
        if (bars.length === 0)
            return "error: no bar on screen";
        var screen = bars[0].modelData ? bars[0].modelData.name : "";
        root.debugJoin = { edge: edge, x: x, width: width, screen: screen };
        Core.PanelRegistry.setJoin(root, root.debugJoin);
        return "ok";
    }

    function joinClear(): string {
        root.debugJoin = null;
        Core.PanelRegistry.clearJoin(root);
        return "ok";
    }

    // `qs ipc call debug query "<text>"`, ranks a query against the live
    // menu tree without opening the surface (no keyboard injection in a
    // nested test session); verifies the apps provider + fuzzy filtering.
    function query(q: string): string {
        return JSON.stringify(menu ? menu.query(q) : []);
    }
}
