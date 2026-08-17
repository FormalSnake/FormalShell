import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import "../../Display/outputs.js" as Outputs

// Hyprland backend over Quickshell's native Hyprland IPC module. Hyprland.workspaces/
// toplevels/monitors are already-reactive ObjectModels (unlike niri's raw socket, no
// event-reducer needed here) - this file only maps their shapes onto the contract and
// dispatches actions. Every dispatch branches on Hyprland.usingLua (Hyprland >=0.55's
// Lua config migration changed dispatcher call syntax; there is no upstream shim), e.g.
// focusWorkspace: Lua -> hl.dsp.focus({workspace=...}), legacy -> "workspace <id>".
// Portions from DankMaterialShell (MIT, Copyright 2025 Avenge Media LLC).
Scope {
    id: root

    // No exposed "connected" bool on Hyprland's IPC singleton (unlike niri's socket
    // state) - CompositorService only instantiates this backend once
    // HYPRLAND_INSTANCE_SIGNATURE is already detected, so a populated monitor list is
    // the available signal: it means the IPC round-trip actually returned data.
    readonly property bool available: Hyprland.monitors.values.length > 0

    readonly property var workspaces: Hyprland.workspaces.values.map(function (w) {
        return {
            id: String(w.id),
            idx: w.id,
            name: w.name ?? "",
            output: w.monitor ? w.monitor.name : "",
            isActive: w.active,
            isFocused: w.focused,
            isUrgent: w.urgent
        };
    })

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
    // and :277 — none of the movewindowv2/openwindow/fullscreen event
    // branches refresh it). A window moved or resized since then reports
    // where it used to be. Good enough to HINT a rectangle in the picker;
    // never good enough to CROP from. Anything cropping must re-read
    // `hyprctl clients -j` at capture time.
    readonly property var windows: Hyprland.toplevels.values.map(function (t) {
        var ipc = t.lastIpcObject || {};
        var at = ipc.at;
        var size = ipc.size;
        var hasRect = !(ipc.hidden ?? false)
            && Array.isArray(at) && Array.isArray(size)
            && size[0] > 0 && size[1] > 0;
        return {
            id: t.address,
            title: t.title,
            appId: ipc.class ?? "",
            workspaceId: t.workspace ? String(t.workspace.id) : "",
            isFocused: t.activated,
            isFloating: ipc.floating ?? false,
            isUrgent: t.urgent,
            rect: hasRect ? { x: at[0], y: at[1], width: size[0], height: size[1] } : null
        };
    })

    // Not derived from Hyprland.monitors, unlike everything else here:
    // Quickshell populates that model from `j/monitors`, which omits disabled
    // monitors entirely (connection.cpp:805 there) — an output switched off
    // would vanish from the very list DisplayPanel needs to switch it back on
    // from. `hyprctl monitors all -j` is the only enumeration that includes
    // them, and it carries `disabled`/`mirrorOf` too, which the model doesn't
    // expose at all.
    property var outputs: []

    readonly property string focusedWindowId: Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
    readonly property string focusedWorkspaceId: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : ""
    readonly property string focusedOutputName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

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

    // Hyprland's exec dispatcher takes one shell command string, not an argv array
    // (unlike niri's structured Spawn action) - quote each arg so it survives that
    // shell unmodified rather than being word-split or glob-expanded.
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

    // No niri-border.kdl equivalent on Hyprland (M3 ships the fragment for
    // niri only) — no-op, matching BackendBase's contract default.
    function applyThemeFragment() {}

    readonly property bool outputConfigAvailable: true
    readonly property bool mirrorSupported: true

    // Output configuration goes through `hyprctl keyword monitor` rather than
    // Hyprland.dispatch(): monitor layout is a config keyword, not a
    // dispatcher, and Quickshell exposes only dispatch() plus the request
    // socket's path (qml.hpp:52 there) — makeRequest() itself is C++-private.
    // hyprctl is guaranteed present wherever HYPRLAND_INSTANCE_SIGNATURE is
    // set, and that env guard matters: CompositorService instantiates every
    // backend regardless of which one it goes on to select, so without it a
    // niri session would spawn a doomed hyprctl on startup — the same reason
    // NiriBackend's own _connect() bails on an empty socket path.
    function refreshOutputs() {
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || outputsProc.running)
            return;
        outputsProc.running = true;
    }

    // Output names are plain strings on the wire on both compositors — the
    // `monitor` keyword takes the name verbatim — so none of the requests
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
            // last good list on screen — a stale row is not the truth. But it
            // is flagged as a FAILURE rather than as an empty result, so the
            // panel says so instead of claiming the session has no displays.
            if (exitCode !== 0) {
                root.outputs = [];
                root.outputsState = "failed";
                return;
            }
            root.outputs = Outputs.parseHyprlandOutputs(outputsCollector.text);
            root.outputsState = "ok";
        }
    }

    // Hyprland applies a monitor keyword before hyprctl exits, so unlike
    // niri's idle-scheduled Output request this needs no settling delay — but
    // the re-read waits until the whole queue has drained, so a mirror of
    // three outputs reports once, not once per leg.
    Process {
        id: keywordProc
        onExited: {
            if (root._keywordQueue.length > 0)
                root._drainKeywords();
            else
                root.refreshOutputs();
        }
    }

    Component.onCompleted: root.refreshOutputs()

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
