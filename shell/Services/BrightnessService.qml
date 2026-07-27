pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Backlight control via `brightnessctl -m` (machine-readable CSV: name,
// class,current,percent%,max — verified against the installed 0.5 binary's
// actual output, not the man page). `-c backlight` scopes the device list to
// the screen backlight only; brightnessctl also reports keyboard/lan/caps-
// lock LED classes under the same `-l`, which we never want here. No polling
// loop: the device list is queried once when the singleton is first touched
// (Component.onCompleted, same lazy-instantiation trigger AudioService relies
// on) and percent is re-read straight from set()/step()'s own machine-
// readable reply — brightnessctl rounds to the device's step granularity, so
// the requested percentage and the applied one can differ.
Singleton {
    id: root

    readonly property bool available: root._device !== ""
    property real percent: 0

    property string _device: ""

    function set(pct) {
        if (!root.available)
            return;
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        setProc.command = ["brightnessctl", "-m", "-d", root._device, "set", clamped + "%"];
        setProc.running = true;
    }

    function step(delta) {
        if (!root.available)
            return;
        const rounded = Math.round(delta);
        const arg = rounded >= 0 ? ("+" + rounded + "%") : ((-rounded) + "%-");
        setProc.command = ["brightnessctl", "-m", "-d", root._device, "set", arg];
        setProc.running = true;
    }

    function _applyCsv(line) {
        const fields = line.split(",");
        if (fields.length < 4)
            return;
        root._device = fields[0];
        root.percent = parseInt(fields[3], 10) || 0;
    }

    Component.onCompleted: listProc.running = true;

    Process {
        id: listProc
        command: ["brightnessctl", "-m", "-c", "backlight", "-l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.split("\n")[0] || "";
                if (line === "") {
                    root._device = "";
                    root.percent = 0;
                    return;
                }
                root._applyCsv(line);
            }
        }
    }

    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: root._applyCsv(text.trim())
        }
    }
}
