pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../Compositor/keyboard.js" as Keyboard

// Keyboard layout state for every bar (Bar.qml is instantiated once per
// output, so this lives here rather than in the cell). One `hyprctl devices
// -j` query at boot and on `configreloaded`, the only event after which the
// configured layout list can differ; `activelayout` carries the new active
// name itself and updates the layout in place, so nothing here polls.
Singleton {
    id: root

    property var layout: Keyboard.unavailable()
    property bool answered: false

    function _query() {
        if (proc.running)
            return;
        proc.running = true;
    }

    Component.onCompleted: root._query()

    Process {
        id: proc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            root.answered = true;
            if (exitCode !== 0) {
                root.layout = Keyboard.unavailable();
                return;
            }
            root.layout = Keyboard.parseHyprlandLayouts(collector.text);
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root._query();
            else if (event.name === "activelayout")
                root.layout = Keyboard.applyActiveLayout(root.layout, event.data);
        }
    }
}
