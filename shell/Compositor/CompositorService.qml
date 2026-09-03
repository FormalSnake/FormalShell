pragma Singleton
import Quickshell
import QtQuick

import qs.Compositor.hyprland
import qs.Core
import "focus.js" as Focus

Singleton {
    id: root

    // Hyprland is the only backend, so there is nothing to detect. A session
    // that is not Hyprland gets the backend's own `available: false` and the
    // honest unavailable state every surface already renders off it, which is
    // also what `debug dump` reports next to this name.
    readonly property string compositor: "hyprland"

    HyprlandBackend {
        id: hyprlandBackend
    }

    readonly property QtObject backend: hyprlandBackend

    readonly property bool available: backend.available
    property var workspaces: backend.workspaces
    property var windows: backend.windows
    property var outputs: backend.outputs
    property var fullscreenOutputs: backend.fullscreenOutputs
    // Whether a surface should hide on an output while a fullscreen window
    // covers it (Config.get default true). Off keeps the bar, frame and hot
    // corners mapped through fullscreen, at the cost of the game never
    // reaching direct scanout.
    readonly property bool hideChromeOnFullscreen: Config.get("fullscreen.hideChrome", true)
    // True when `name` is an output whose focused fullscreen window covers it
    // AND the auto-hide is enabled. Surfaces read `fullscreenOutputs` through
    // this so the binding tracks both.
    function outputCoveredByFullscreen(name) {
        return root.hideChromeOnFullscreen && root.fullscreenOutputs.indexOf(name) >= 0;
    }

    property string focusedWindowId: backend.focusedWindowId
    property string focusedWorkspaceId: backend.focusedWorkspaceId
    property string focusedOutputName: backend.focusedOutputName

    // Last id the compositor actually reported, kept so focus.js can hold it
    // through the stretches where the compositor reports none.
    property string _rememberedFocusedId: ""
    onFocusedWindowIdChanged: if (root.focusedWindowId !== "") root._rememberedFocusedId = root.focusedWindowId

    // focus.js's held focus, what a bar cell naming the current app should
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
