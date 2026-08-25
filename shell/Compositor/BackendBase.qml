import QtQuick

// The CompositorBackend contract. Every per-compositor backend (niri, hyprland, ...)
// composes on top of this as its root object. CompositorService holds one active
// backend and delegates the same surface to it.
QtObject {
    id: root

    readonly property bool available: false // backend detected its compositor and is connected

    property var workspaces: [] // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
    // `rect` is the window's box in LOGICAL compositor coordinates, the same
    // space `outputs` rows use, and the space grim/slurp geometry is expressed
    // in. It is `null`, never a zeroed box, whenever the compositor did not
    // report a geometry for that window: a window with no box must not become
    // a rectangle at the origin, which the capture picker would happily
    // highlight and crop to.
    property var windows: [] // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool, rect:{x,y,width,height}|null }]
    // Display/outputs.js's row contract, see its header for the full shape
    // and for why a disabled output reports a zero mode rather than its last
    // known one. Populated only by refreshOutputs() below; neither compositor
    // pushes output changes over its event stream.
    property var outputs: [] // [{ name, make, model, x, y, width, height, refresh, scale, enabled, mirrorOf }]

    // "unknown" (no enumeration has answered yet) | "ok" | "failed". An empty
    // `outputs` is ambiguous on its own, "the compositor reports none" and
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

    // Webcam overlay placement (M27 Task 5): whether this backend can move an
    // arbitrary window into the floating layout at an absolute pixel size and
    // position. False here, the null backend's answer for "no compositor
    // detected" -- RecordingService checks this before ever spawning the
    // overlay, so an unsupported compositor never leaves an unplaceable mpv
    // window sitting mid-recording.
    readonly property bool floatingPlacementAvailable: false
    // Idempotent: makes `id` floating if it isn't already. Never toggles a
    // window that already is, since a fresh recording always calls this once
    // right after the window maps.
    function floatWindow(id) {}
    // Resizes and moves an already-floating `id` to width x height at the
    // absolute logical position (x, y) -- the same space `windows[].rect`
    // reports. Callers only invoke this once a poll on `windows` has already
    // confirmed `id` carries a non-null `rect`.
    function placeFloatingWindow(id, x, y, width, height) {}

    // Parking (M37): moving a window out of view and back without touching
    // focus, which is what a quake console's toggle is made of. False here,
    // the null backend's answer for "no compositor detected", ConsoleService
    // checks it before spawning anything, so a compositor that cannot park
    // never gets a console it would be unable to hide again.
    readonly property bool windowParkingAvailable: false
    // Out of view. Hyprland hides the special workspace the window lives on;
    // niri, with no hide primitive at all, moves the window to another
    // workspace (park.js picks which). Focus stays where it is on both.
    function parkWindow(id) {}
    // Back into view where the user is looking, still without focusing it,
    // the caller places the window first and focuses it once it has landed,
    // so it never appears at its old size for a frame.
    function unparkWindow(id) {}
    // Whether `id` is currently out of view. Not the same question as "which
    // workspace is it on": Hyprland's console never leaves its special
    // workspace, and that workspace is either drawn over the current one or
    // not. Callers read this instead of comparing workspace ids themselves.
    function isWindowParked(id) { return true }

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
