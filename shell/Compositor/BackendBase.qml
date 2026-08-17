import QtQuick

// The CompositorBackend contract. Every per-compositor backend (niri, hyprland, ...)
// composes on top of this as its root object. CompositorService holds one active
// backend and delegates the same surface to it.
QtObject {
    id: root

    readonly property bool available: false // backend detected its compositor and is connected

    property var workspaces: [] // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
    // `rect` is the window's box in LOGICAL compositor coordinates — the same
    // space `outputs` rows use, and the space grim/slurp geometry is expressed
    // in. It is `null`, never a zeroed box, whenever the compositor did not
    // report a geometry for that window: a window with no box must not become
    // a rectangle at the origin, which the capture picker would happily
    // highlight and crop to.
    property var windows: [] // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool, rect:{x,y,width,height}|null }]
    // Display/outputs.js's row contract — see its header for the full shape
    // and for why a disabled output reports a zero mode rather than its last
    // known one. Populated only by refreshOutputs() below; neither compositor
    // pushes output changes over its event stream.
    property var outputs: [] // [{ name, make, model, x, y, width, height, refresh, scale, enabled, mirrorOf }]

    // "unknown" (no enumeration has answered yet) | "ok" | "failed". An empty
    // `outputs` is ambiguous on its own — "the compositor reports none" and
    // "the query failed" are different facts, and only the first one licenses
    // the panel's NO OUTPUTS cell. Without this a transiently failing
    // hyprctl/niri query tells a session with two lit monitors it has none.
    property string outputsState: "unknown"

    property string focusedWindowId: ""
    property string focusedWorkspaceId: ""
    property string focusedOutputName: ""

    signal configReloaded(bool failed)

    function focusWorkspace(id) {}
    function focusWindow(id) {}
    function closeWindow(id) {}
    function spawn(argv) {} // argv: list<string>, no shell interpolation
    function powerOffMonitors() {}
    function powerOnMonitors() {}
    function applyThemeFragment() {} // niri-only; no-op on backends without one

    // Re-reads `windows`; never moves or focuses anything. A backend whose
    // window model is already event-driven leaves this a no-op. It exists for
    // Hyprland, where the box in `rect` goes stale between refreshes, so
    // anything about to CROP to a window (the capture picker) can ask for a
    // current one first rather than capturing where the window used to be.
    function refreshWindows() {}

    // Output management (DisplayPanel). `outputs` above is the read model;
    // these are the writes, and both capability flags exist so the panel can
    // render an honest unavailable cell instead of a control that would
    // silently do nothing: `outputConfigAvailable` is false wherever no
    // compositor was detected at all, `mirrorSupported` false wherever the
    // compositor has no mirroring primitive to drive (niri).
    readonly property bool outputConfigAvailable: false
    readonly property bool mirrorSupported: false

    function refreshOutputs() {} // re-reads `outputs`; never reconfigures anything
    function setOutputEnabled(name, enabled) {}
    function setOutputScale(name, scale) {}
    function setOutputMirror(name, sourceName) {} // sourceName "" ends the mirror
}
