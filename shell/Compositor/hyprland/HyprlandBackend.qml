import QtQuick
import Quickshell
import Quickshell.Hyprland

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

    readonly property var windows: Hyprland.toplevels.values.map(function (t) {
        var ipc = t.lastIpcObject || {};
        return {
            id: t.address,
            title: t.title,
            appId: ipc.class ?? "",
            workspaceId: t.workspace ? String(t.workspace.id) : "",
            isFocused: t.activated,
            isFloating: ipc.floating ?? false,
            isUrgent: t.urgent
        };
    })

    readonly property var outputs: Hyprland.monitors.values.map(function (m) {
        return { name: m.name, x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale };
    })

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

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.configReloaded(false);
        }
    }
}
