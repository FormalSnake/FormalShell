pragma Singleton
import Quickshell
import QtQuick

import qs.Compositor.niri

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

    // Task 9 extends this to also pick a HyprlandBackend.
    readonly property QtObject backend: root.compositor === "niri" ? niriBackend : nullBackend

    readonly property bool available: backend.available
    property var workspaces: backend.workspaces
    property var windows: backend.windows
    property var outputs: backend.outputs
    property string focusedWindowId: backend.focusedWindowId
    property string focusedWorkspaceId: backend.focusedWorkspaceId
    property string focusedOutputName: backend.focusedOutputName

    signal configReloaded(bool failed)

    function focusWorkspace(id) { backend.focusWorkspace(id) }
    function focusWindow(id) { backend.focusWindow(id) }
    function closeWindow(id) { backend.closeWindow(id) }
    function spawn(argv) { backend.spawn(argv) }
    function powerOffMonitors() { backend.powerOffMonitors() }
    function powerOnMonitors() { backend.powerOnMonitors() }

    Connections {
        target: backend
        function onConfigReloaded(failed) { root.configReloaded(failed) }
    }

    readonly property var ext: ({
        overview: { available: false, isOpen: false, toggle: function () {} }
    })
}
