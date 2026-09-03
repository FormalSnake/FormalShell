import QtQuick
import QtQml
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import "../../Display/outputs.js" as Outputs
import "model.js" as Model

// Hyprland backend over Quickshell's native Hyprland IPC module. Hyprland.workspaces/
// toplevels/monitors are already-reactive ObjectModels, so this file only maps their
// shapes onto the contract and dispatches actions. Every dispatch branches on Hyprland.usingLua (Hyprland >=0.55's
// Lua config migration changed dispatcher call syntax; there is no upstream shim), e.g.
// focusWorkspace: Lua -> hl.dsp.focus({workspace=...}), legacy -> "workspace <id>".
// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC).
Scope {
    id: root

    // No exposed "connected" bool on Hyprland's IPC singleton, so a populated monitor
    // list is the available signal: it means the IPC round-trip actually returned data.
    // A session that is not Hyprland never gets one, which is this backend's own honest
    // unavailable state.
    readonly property bool available: Hyprland.monitors.values.length > 0

    // Shape and the special-workspace exclusion both live in model.js; see its
    // header for why an overlay workspace is not a workspace here.
    readonly property var _mappedWorkspaces: Model.mapWorkspaces(Hyprland.workspaces.values)

    // `at`/`size` are already logical coordinates, so they map straight onto
    // the BackendBase `rect` contract. A hidden window (an unfocused member of
    // a tabbed group) still carries its group's box; it is excluded rather
    // than reported, because nothing can be captured through it and a
    // duplicate box stalls the picker's Tab cycle on the first copy.
    //
    // ⚠️ This box can be STALE. Quickshell only repopulates `lastIpcObject`
    // from `j/clients` on connect and on `configreloaded` (verified in the
    // pinned quickshell 43d4fa9: refreshToplevels() is defined at
    // src/wayland/hyprland/ipc/connection.cpp:705 and called only from :92
    // and :277, none of the movewindowv2/openwindow/fullscreen event
    // branches refresh it). A window moved or resized since then reports
    // where it used to be. Good enough to HINT a rectangle in the picker;
    // never good enough to CROP from. Anything cropping must re-read
    // `hyprctl clients -j` at capture time.
    readonly property var _mappedWindows: Hyprland.toplevels.values.map(function (t) {
        var ipc = t.lastIpcObject || {};
        var at = ipc.at;
        var size = ipc.size;
        // Length-and-index, not Array.isArray: `lastIpcObject` is a
        // QVariantMap, and its nested QVariantList values reach QML as
        // list-like objects that index and measure fine but answer false to
        // Array.isArray. Every window on Hyprland therefore reported a null
        // rect while `hyprctl clients -j` had real boxes for all of them,
        // which silently disabled the capture picker's window crop and the
        // quake console's placement (2026-08-19).
        var hasRect = !(ipc.hidden ?? false)
            && at && size && at.length >= 2 && size.length >= 2
            && size[0] > 0 && size[1] > 0;
        return {
            id: t.address,
            title: t.title,
            // The wlr-foreign-toplevel handle's own app id, which arrives
            // with the window and updates on its own events. `lastIpcObject`
            // is the fallback, not the source: Quickshell only repopulates it
            // from `j/clients` on connect and on configreloaded (see the
            // comment above), so a window opened since startup reported an
            // EMPTY app id here until something forced a refresh. Anything
            // matching a freshly spawned window by app id, the quake
            // console, the recorder's webcam overlay, silently never found
            // it (2026-08-19).
            appId: (t.wayland && t.wayland.appId) ? t.wayland.appId : (ipc.class ?? ""),
            workspaceId: t.workspace ? String(t.workspace.id) : "",
            isFocused: t.activated,
            isFloating: ipc.floating ?? false,
            isUrgent: t.urgent,
            rect: hasRect ? { x: at[0], y: at[1], width: size[0], height: size[1] } : null
        };
    })

    // Hyprland sends several events per user action, browser title changes
    // arrive on their own, and consumers re-derive everything they show from
    // a fresh `windows` array, so the mapped arrays are published rather than
    // bound straight through. The two
    // bindings above stay bindings so QML keeps tracking every dependency the
    // mapping reads (each model's `values`, and per toplevel `title`,
    // `activated`, `urgent`, `workspace`, `lastIpcObject` and the wayland
    // handle's `appId`); their handlers only schedule. A burst of events in
    // one event-loop turn then publishes once, and a publication whose mapped
    // shape equals the last one is dropped entirely. Kept apart so a window
    // title change cannot republish `workspaces`.
    property var workspaces: []
    property var windows: []

    property string _workspacesJson: ""
    property string _windowsJson: ""
    property bool _workspacesQueued: false
    property bool _windowsQueued: false

    on_MappedWorkspacesChanged: {
        if (root._workspacesQueued)
            return;
        root._workspacesQueued = true;
        Qt.callLater(root._publishWorkspaces);
    }

    on_MappedWindowsChanged: {
        if (root._windowsQueued)
            return;
        root._windowsQueued = true;
        Qt.callLater(root._publishWindows);
    }

    // Both read the binding at call time rather than a value captured when the
    // publication was scheduled, so the last event of the turn is the one that
    // reaches consumers.
    function _publishWorkspaces() {
        root._workspacesQueued = false;
        var next = root._mappedWorkspaces;
        var json = JSON.stringify(next);
        if (json === root._workspacesJson)
            return;
        root._workspacesJson = json;
        root.workspaces = next;
    }

    function _publishWindows() {
        root._windowsQueued = false;
        var next = root._mappedWindows;
        var json = JSON.stringify(next);
        if (json === root._windowsJson)
            return;
        root._windowsJson = json;
        root.windows = next;
    }

    // Not derived from Hyprland.monitors, unlike everything else here:
    // Quickshell populates that model from `j/monitors`, which omits disabled
    // monitors entirely (connection.cpp:805 there), an output switched off
    // would vanish from the very list DisplayPanel needs to switch it back on
    // from. `hyprctl monitors all -j` is the only enumeration that includes
    // them, and it carries `disabled`/`mirrorOf` too, which the model doesn't
    // expose at all.
    property var outputs: []
    property string _outputsJson: "[]"
    // Declared here, not inherited: this backend is a Scope and BackendBase
    // is a contract on paper, so every property on it has to be repeated.
    // Without this one the assignments in outputsProc below hit no property
    // at all and DisplayPanel read undefined off it, which is its LOADING
    // state, so an empty list never reached NO OUTPUTS or CANNOT READ
    // OUTPUTS (e1504g, 2026-08-26).
    property string outputsState: "unknown"

    readonly property string focusedWindowId: Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
    readonly property string focusedWorkspaceId: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : ""
    readonly property string focusedOutputName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // Outputs whose focused fullscreen window covers them, so a surface that
    // would otherwise sit on the overlay/top layer can hide and let the game
    // reach Hyprland's solitary / direct-scanout fast path. That path is off
    // whenever anything at all is mapped above the fullscreen window, so the
    // panel then tracks the compositor's own repaint clock instead of the
    // game's frame timing (VRR never follows the game) and every frame pays a
    // full composite. Recomputed from three event-driven signals, never the
    // stale `lastIpcObject`: the wlr-foreign-toplevel `fullscreen` and
    // `activated` flags (pinned quickshell 43d4fa9, src/wayland/toplevel/
    // qml.hpp:33,54) and the Hyprland-native `monitor` the window sits on
    // (ipc/hyprland_toplevel.hpp:49). Keyed on `activated` on purpose: a
    // window left fullscreen on a now-hidden workspace, or one the user has
    // tabbed away from, is no longer activated, so its output drops out of the
    // set and the chrome comes straight back. Anything the query cannot answer
    // yet (a toplevel whose wayland handle or monitor has not been reported)
    // leaves the set empty for that window, which shows the chrome: the safe
    // direction.
    property var fullscreenOutputs: []
    property string _fullscreenOutputsJson: "[]"

    function _recomputeFullscreen() {
        var out = ({});
        var tls = Hyprland.toplevels.values;
        for (var i = 0; i < tls.length; i++) {
            var h = tls[i];
            var w = h.wayland;
            if (w && w.fullscreen && h.activated && h.monitor && h.monitor.name)
                out[h.monitor.name] = true;
        }
        var next = Object.keys(out).sort();
        var json = JSON.stringify(next);
        if (json === root._fullscreenOutputsJson)
            return;
        root._fullscreenOutputsJson = json;
        root.fullscreenOutputs = next;
    }

    // One tracker object per toplevel. Its bindings read every reactive input
    // the set depends on (the foreign-toplevel handle, its `fullscreen` and
    // `activated`, and the Hyprland monitor's name), so a change to any of
    // them re-fires the handler and republishes. Reacting to the bindings
    // rather than to Hyprland's event stream sidesteps the race where the IPC
    // `fullscreen` event and the wlr state change arrive a frame apart.
    Instantiator {
        model: Hyprland.toplevels
        delegate: QtObject {
            required property var modelData
            readonly property var _w: modelData ? modelData.wayland : null
            readonly property bool _covering: !!_w && _w.fullscreen
                && !!modelData && modelData.activated && !!modelData.monitor
            readonly property string _out: (modelData && modelData.monitor) ? modelData.monitor.name : ""
            on_CoveringChanged: root._recomputeFullscreen()
            on_OutChanged: root._recomputeFullscreen()
            Component.onCompleted: root._recomputeFullscreen()
            Component.onDestruction: root._recomputeFullscreen()
        }
    }

    signal configReloaded(bool failed)

    // Hyprland's own JSON IPC value quoting for lua dispatcher args (mirrors DMS's
    // HyprlandService.qml luaString/luaValue helpers).
    function _luaString(value) {
        return "\"" + String(value ?? "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }
    function _luaValue(value) {
        var text = String(value ?? "");
        return /^[-+]?\d+$/.test(text) ? text : root._luaString(text);
    }

    // Window ids are Hyprland's hex address, kept verbatim (no "0x" prefix, per
    // HyprlandToplevel.address); dispatchers want an "address:0x..." selector.
    function _windowSelector(id) {
        var addr = String(id ?? "");
        return "address:" + (addr.indexOf("0x") === 0 ? addr : "0x" + addr);
    }

    // Hyprland's exec dispatcher takes one shell command string, not an argv array, so
    // quote each arg to survive that shell unmodified rather than being word-split or
    // glob-expanded.
    function _quoteArg(arg) {
        return "'" + String(arg).replace(/'/g, "'\\''") + "'";
    }

    // Quickshell repopulates `lastIpcObject` from `j/clients` only on connect
    // and on configreloaded (pinned quickshell 43d4fa9,
    // src/wayland/hyprland/ipc/connection.cpp:705, called from :92 and :277
    // only), so a window opened since startup carries no `at`/`size` at all
    // and every window moved since then reports a stale box. Both make
    // `rect` above lie. `refreshToplevels` is the module's own escape hatch
    // for exactly this and is Q_INVOKABLE on the QML singleton
    // (ipc/qml.hpp:73); it re-reads `j/clients` rather than dispatching
    // anything, so it cannot move a window.
    function refreshWindows() {
        Hyprland.refreshToplevels();
    }

    function focusWorkspace(id) {
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + root._luaValue(id) + " })");
        else
            Hyprland.dispatch("workspace " + id);
    }

    function focusWindow(id) {
        var selector = root._windowSelector(id);
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.focus({ window = " + root._luaString(selector) + " })");
        else
            Hyprland.dispatch("focuswindow " + selector);
    }

    function closeWindow(id) {
        var selector = root._windowSelector(id);
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.window.close(" + root._luaString(selector) + ")");
        else
            Hyprland.dispatch("closewindow " + selector);
    }

    function spawn(argv) {
        var cmd = argv.map(root._quoteArg).join(" ");
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.exec_cmd(" + root._luaString(cmd) + ")");
        else
            Hyprland.dispatch("exec " + cmd);
    }

    function powerOffMonitors() {
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.dpms({ action = \"disable\" })");
        else
            Hyprland.dispatch("dpms off");
    }

    function powerOnMonitors() {
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.dpms({ action = \"enable\" })");
        else
            Hyprland.dispatch("dpms on");
    }

    // Webcam overlay placement (M27 Task 5), the exact dual dispatch
    // omarchy-capture-webcam-resize's own hypr_dispatch already establishes
    // (Lua hl.dsp.window.* first, legacy dispatcher string on Hyprland <0.55,
    // MIT). `setfloating` is a toggle in the legacy dispatcher, unlike Lua's
    // `action = "set"`, so both branches skip the call once `isFloating` is
    // already true rather than risk tiling a window back.
    readonly property bool floatingPlacementAvailable: true

    // The three lookups below read `_mappedWindows`, not the published list: a
    // dispatch decided in the same turn as the event that changed the window
    // would otherwise be made against a list one turn old.
    function floatWindow(id) {
        const w = root._mappedWindows.find(win => win.id === id);
        if (w && w.isFloating)
            return;
        const selector = root._windowSelector(id);
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.window.float({ window = " + root._luaString(selector) + ", action = \"set\" })");
        else
            Hyprland.dispatch("setfloating " + selector);
    }

    // Parking (M37), the primitive omarchy's own Quake console is built on
    // (default/hypr/qconsole.lua): a special workspace is an overlay that is
    // simply not on screen until something toggles it. So the console LIVES
    // there permanently and showing it is the compositor's own toggle, which
    // is what makes it drop down and retract under the `specialWorkspace`
    // animation instead of being carried between workspaces a window at a
    // time.
    readonly property bool windowParkingAvailable: true
    readonly property string _parkWorkspace: "special:formalshell-console"

    // Whether the focused monitor is currently showing our special workspace.
    // `j/monitors`' own `specialWorkspace` field is the only place Hyprland
    // reports this; refreshMonitors() below keeps it current, and nothing but
    // the two toggles here can change it.
    function _specialShown() {
        const m = Hyprland.focusedMonitor;
        const ipc = m ? (m.lastIpcObject || {}) : {};
        const special = ipc.specialWorkspace;
        return !!special && String(special.name ?? "") === root._parkWorkspace;
    }

    function _toggleSpecial() {
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + root._luaString("formalshell-console") + ")");
        else
            Hyprland.dispatch("togglespecialworkspace formalshell-console");
        Hyprland.refreshMonitors();
    }

    // Idempotent: a window already on the special workspace stays put.
    function _moveToSpecial(id) {
        const win = root._mappedWindows.find(w => w.id === id);
        if (win && Number(win.workspaceId) < 0)
            return;
        const selector = root._windowSelector(id);
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.window.move({ window = " + root._luaString(selector)
                + ", workspace = " + root._luaString(root._parkWorkspace) + ", follow = false })");
        else
            Hyprland.dispatch("movetoworkspacesilent " + root._parkWorkspace + "," + selector);
    }

    function parkWindow(id) {
        root._moveToSpecial(id);
        if (root._specialShown())
            root._toggleSpecial();
    }

    function unparkWindow(id) {
        root._moveToSpecial(id);
        if (!root._specialShown())
            root._toggleSpecial();
    }

    // On the special workspace and not on screen, or on some other workspace
    // than the one being looked at. A window this backend has never heard of
    // counts as parked: the console's toggle then asks for it to be brought
    // here, which is the recoverable answer.
    function isWindowParked(id) {
        const win = root._mappedWindows.find(w => w.id === id);
        if (!win)
            return true;
        if (Number(win.workspaceId) < 0)
            return !root._specialShown();
        return win.workspaceId !== root.focusedWorkspaceId;
    }

    function placeFloatingWindow(id, x, y, width, height) {
        const selector = root._windowSelector(id);
        const w = Math.max(1, Math.round(width));
        const h = Math.max(1, Math.round(height));
        const px = Math.round(x);
        const py = Math.round(y);
        if (Hyprland.usingLua) {
            Hyprland.dispatch("hl.dsp.window.resize({ window = " + root._luaString(selector) + ", x = " + w + ", y = " + h + " })");
            Hyprland.dispatch("hl.dsp.window.move({ window = " + root._luaString(selector) + ", x = " + px + ", y = " + py + " })");
        } else {
            Hyprland.dispatch("resizewindowpixel exact " + w + " " + h + "," + selector);
            Hyprland.dispatch("movewindowpixel exact " + px + " " + py + "," + selector);
        }
    }

    readonly property bool outputConfigAvailable: true
    readonly property bool mirrorSupported: true

    // Output configuration goes through `hyprctl keyword monitor` rather than
    // Hyprland.dispatch(): monitor layout is a config keyword, not a
    // dispatcher, and Quickshell exposes only dispatch() plus the request
    // socket's path (qml.hpp:52 there), makeRequest() itself is C++-private.
    // hyprctl is guaranteed present wherever HYPRLAND_INSTANCE_SIGNATURE is
    // set, and that env guard matters: this backend is instantiated
    // unconditionally, so without it a session that is not Hyprland would
    // spawn a doomed hyprctl on startup and on every refresh after.
    function refreshOutputs() {
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || outputsProc.running)
            return;
        outputsProc.running = true;
    }

    // Output names are plain strings on the wire and the `monitor` keyword
    // takes the name verbatim, so none of the requests
    // below carry any id conversion, unlike the window selectors above.
    function setOutputEnabled(name, enabled) {
        // Re-enabling deliberately re-derives the mode, position and scale
        // (`preferred,auto,auto`) instead of restating the row's own: a
        // disabled monitor reports a zero mode, so there is nothing truthful
        // left to restate.
        root._keyword(enabled ? name + ",preferred,auto,auto" : name + ",disable");
    }

    function setOutputScale(name, scale) {
        var row = Outputs.findOutput(root.outputs, name);
        if (!row)
            return;
        root._keyword(Outputs.hyprlandMonitorArg(row, { scale: scale }));
    }

    function setOutputMirror(name, sourceName) {
        var row = Outputs.findOutput(root.outputs, name);
        if (!row)
            return;
        root._keyword(Outputs.hyprlandMonitorArg(row, { mirrorOf: sourceName }));
    }

    // MIRROR fires one keyword per mirrored output at once, so these queue:
    // reassigning a Process's command while it is still running would drop
    // the in-flight invocation on the floor, silently losing a user action.
    property var _keywordQueue: []

    function _keyword(monitorArg) {
        root._keywordQueue = root._keywordQueue.concat([monitorArg]);
        root._drainKeywords();
    }

    function _drainKeywords() {
        if (keywordProc.running || root._keywordQueue.length === 0)
            return;
        var next = root._keywordQueue[0];
        root._keywordQueue = root._keywordQueue.slice(1);
        keywordProc.command = ["hyprctl", "keyword", "monitor", next];
        keywordProc.running = true;
    }

    Process {
        id: outputsProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            id: outputsCollector
        }
        onExited: exitCode => {
            // A failed enumeration reports nothing rather than leaving the
            // last good list on screen, a stale row is not the truth. But it
            // is flagged as a FAILURE rather than as an empty result, so the
            // panel says so instead of claiming the session has no displays.
            var next = exitCode !== 0 ? [] : Outputs.parseHyprlandOutputs(outputsCollector.text);
            var json = JSON.stringify(next);
            if (json !== root._outputsJson) {
                root._outputsJson = json;
                root.outputs = next;
            }
            root.outputsState = exitCode !== 0 ? "failed" : "ok";
        }
    }

    // Hyprland applies a monitor keyword before hyprctl exits, so no settling
    // delay is needed, but the re-read waits until the whole queue has
    // drained, so a mirror of three outputs reports once, not once per leg.
    Process {
        id: keywordProc
        onExited: {
            if (root._keywordQueue.length > 0)
                root._drainKeywords();
            else
                root.refreshOutputs();
        }
    }

    // Consumers read `windows` before any Hyprland event arrives, so the first
    // publication is not left to one.
    Component.onCompleted: {
        root._publishWorkspaces();
        root._publishWindows();
        root.refreshOutputs();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.configReloaded(false);
                root.refreshOutputs();
            } else if (event.name === "monitoraddedv2" || event.name === "monitorremoved") {
                root.refreshOutputs();
            }
        }
    }
}
