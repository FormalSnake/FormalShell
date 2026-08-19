pragma Singleton
import Quickshell
import QtQuick

import qs.Compositor.niri
import qs.Compositor.hyprland
import "focus.js" as Focus

Singleton {
    id: root

    // TODO(hardening): env-based detection is sufficient inside nested test sessions;
    // DMS walks /proc/net/unix by socket owner for the general case (CompositorService.qml:927).
    readonly property string compositor: {
        if (Quickshell.env("NIRI_SOCKET"))
            return "niri"
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return "hyprland"
        return "unknown"
    }

    BackendBase {
        id: nullBackend
    }

    NiriBackend {
        id: niriBackend
    }

    HyprlandBackend {
        id: hyprlandBackend
    }

    readonly property QtObject backend: {
        if (root.compositor === "niri") return niriBackend;
        if (root.compositor === "hyprland") return hyprlandBackend;
        return nullBackend;
    }

    readonly property bool available: backend.available
    property var workspaces: backend.workspaces
    property var windows: backend.windows
    property var outputs: backend.outputs
    property string focusedWindowId: backend.focusedWindowId
    property string focusedWorkspaceId: backend.focusedWorkspaceId
    property string focusedOutputName: backend.focusedOutputName

    // Last id the compositor actually reported, kept so focus.js can hold it
    // through the stretches where the compositor reports none.
    property string _rememberedFocusedId: ""
    onFocusedWindowIdChanged: if (root.focusedWindowId !== "") root._rememberedFocusedId = root.focusedWindowId

    // focus.js's held focus — what a bar cell naming the current app should
    // read. Anything that needs the compositor's literal answer (Menu.qml's
    // launch baseline) keeps reading focusedWindowId.
    readonly property string heldFocusedWindowId: Focus.held(root.focusedWindowId, root._rememberedFocusedId, root.windows, root.focusedWorkspaceId)

    function windowById(id) {
        if (id === "")
            return null;
        for (var i = 0; i < root.windows.length; i++) {
            if (root.windows[i].id === id)
                return root.windows[i];
        }
        return null;
    }

    signal configReloaded(bool failed)

    function focusWorkspace(id) { backend.focusWorkspace(id) }
    function focusWindow(id) { backend.focusWindow(id) }
    function closeWindow(id) { backend.closeWindow(id) }
    function spawn(argv) { backend.spawn(argv) }
    function powerOffMonitors() { backend.powerOffMonitors() }
    function powerOnMonitors() { backend.powerOnMonitors() }
    function applyThemeFragment() { backend.applyThemeFragment() }
    function refreshWindows() { backend.refreshWindows() }

    readonly property bool windowParkingAvailable: backend.windowParkingAvailable
    function parkWindow(id) { backend.parkWindow(id) }
    function unparkWindow(id) { backend.unparkWindow(id) }
    function isWindowParked(id) { return backend.isWindowParked(id) }

    readonly property bool floatingPlacementAvailable: backend.floatingPlacementAvailable
    function floatWindow(id) { backend.floatWindow(id) }
    function placeFloatingWindow(id, x, y, width, height) { backend.placeFloatingWindow(id, x, y, width, height) }

    Connections {
        target: backend
        function onConfigReloaded(failed) { root.configReloaded(failed) }
    }

    readonly property var ext: ({
        overview: { available: false, isOpen: false, toggle: function () {} }
    })
}
