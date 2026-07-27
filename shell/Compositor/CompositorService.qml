pragma Singleton
import Quickshell
import QtQuick

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
        id: backend
    }

    readonly property alias available: backend.available
    property alias workspaces: backend.workspaces
    property alias windows: backend.windows
    property alias outputs: backend.outputs
    property alias focusedWindowId: backend.focusedWindowId
    property alias focusedWorkspaceId: backend.focusedWorkspaceId
    property alias focusedOutputName: backend.focusedOutputName

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
