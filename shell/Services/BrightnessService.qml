pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Backlight control via `brightnessctl -m` (machine-readable CSV: name,
// class,current,percent%,max, verified against the installed 0.5 binary's
// actual output, not the man page). `-c backlight` scopes the device list to
// the screen backlight only; brightnessctl also reports keyboard/lan/caps-
// lock LED classes under the same `-l`, which we never want here. No polling
// loop: the device list is queried once when the singleton is first touched
// (Component.onCompleted, same lazy-instantiation trigger AudioService relies
// on) and percent is re-read straight from set()/step()'s own machine-
// readable reply, brightnessctl rounds to the device's step granularity, so
// the requested percentage and the applied one can differ.
Singleton {
    id: root

    readonly property bool available: root._device !== ""
    property real percent: 0

    property string _device: ""

    // Per-monitor brightness (M16 Task 5): `devices` unions the backlight
    // above with any DDC-capable external monitor, one entry per
    // controllable display, `deviceId` "backlight" for the internal panel
    // or a DRM connector name (e.g. "DP-1") for an external one (role
    // named `deviceId` rather than `id`, since `id` is a reserved QML
    // attribute and can't be used as a ListModel role/delegate property).
    // Reimplements the shape of omarchy's omarchy-brightness-display-ddc
    // (I2C-bus detection via `ddcutil detect --brief`, VCP feature 10 for
    // read/write) against this shell's different call pattern: one
    // singleton doing one detect pass per panel open, not a fresh script
    // invocation per keystroke, so the connector->bus cache omarchy keeps
    // in a runtime-dir file is just an in-memory map here, rebuilt on the
    // same cadence (refreshDevices()) instead of a TTL. Detection NEVER
    // runs on a timer, ddcutil's I2C round-trips are seconds-slow, and
    // DisplayPanel.qml is the only caller, from its own onIsOpenChanged. A
    // missing `ddcutil` binary or a detect that finds nothing just leaves
    // the DDC rows empty, identical, honest fallback to today's
    // backlight-only behavior either way.
    //
    // `devices` is a ListModel, not a `property var` JS array: PowerPanel's
    // `Repeater { model: BrightnessService.devices }` used to bind against
    // a freshly-built array every time `percent` changed (every set()/
    // step()/refresh() reply), and Repeater does a full delegate
    // destroy/recreate whenever the model *identity* changes, which
    // dropped the mouse grab mid-drag on the brightness slider. A
    // ListModel has one stable identity; rows are mutated in place
    // (`setProperty`/`insert`/`remove`), so an in-progress drag's
    // MouseArea is never torn down under it.
    readonly property ListModel devices: ListModel {}

    property var _ddcBuses: ({})   // connector -> I2C bus number (string)
    property var _ddcQueue: []     // connectors still awaiting a getvcp read

    function _deviceIndex(id) {
        for (var i = 0; i < root.devices.count; i++) {
            if (root.devices.get(i).deviceId === id)
                return i;
        }
        return -1;
    }

    function _clearDdcRows() {
        for (var i = root.devices.count - 1; i >= 0; i--) {
            if (root.devices.get(i).deviceId !== "backlight")
                root.devices.remove(i);
        }
    }

    function _syncBacklightRow() {
        const idx = root._deviceIndex("backlight");
        if (root.available) {
            if (idx === -1)
                root.devices.insert(0, { deviceId: "backlight", label: "INTERNAL", percent: root.percent, max: 100 });
            else
                root.devices.setProperty(idx, "percent", root.percent);
        } else if (idx !== -1) {
            root.devices.remove(idx);
        }
    }

    onAvailableChanged: root._syncBacklightRow()
    onPercentChanged: root._syncBacklightRow()

    function refreshDevices() {
        root.refresh();
        ddcDetectProc.running = true;
    }

    // id is "backlight" or a DDC connector from `devices` above.
    function setDevicePercent(id, pct) {
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        if (id === "backlight") {
            root.set(clamped);
            return;
        }
        root._setDdc(id, clamped);
    }

    function stepDevicePercent(id, delta) {
        const idx = root._deviceIndex(id);
        if (idx === -1)
            return;
        root.setDevicePercent(id, root.devices.get(idx).percent + delta);
    }

    function _setDdc(connector, pct) {
        const bus = root._ddcBuses[connector];
        const idx = root._deviceIndex(connector);
        if (bus === undefined || idx === -1)
            return;
        const device = root.devices.get(idx);
        // Never write a literal 0% over DDC, omarchy's own floor
        // (../../bin/omarchy-brightness-display-ddc there): some panels
        // treat VCP 10 = 0 as "off", not "dim".
        const target = Math.max(1, pct);
        const raw = Math.round(target * device.max / 100);
        ddcSetvcpProc.command = ["ddcutil", "--bus", bus, "--skip-ddc-checks", "--noverify", "setvcp", "10", String(raw)];
        ddcSetvcpProc.running = true;
        // Optimistic local update: --noverify means setvcp never reads
        // back, and re-running the whole (slow) getvcp chain just to
        // confirm a value this function itself just chose is exactly the
        // poll-loop-shaped cost this file's design avoids.
        root.devices.setProperty(idx, "percent", target);
    }

    function _applyDetect(text) {
        const buses = {};
        const lines = text.split("\n");
        let pendingBus = null;
        for (let i = 0; i < lines.length; i++) {
            const busMatch = /I2C bus:\s*\/dev\/i2c-(\d+)/.exec(lines[i]);
            if (busMatch) {
                pendingBus = busMatch[1];
                continue;
            }
            const connMatch = /DRM connector:\s*card\d+-(\S+)/.exec(lines[i]);
            if (connMatch && pendingBus !== null) {
                buses[connMatch[1]] = pendingBus;
                pendingBus = null;
            }
        }
        root._ddcBuses = buses;
        root._clearDdcRows();
        root._ddcQueue = Object.keys(buses);
        root._pumpDdcQueue();
    }

    function _pumpDdcQueue() {
        if (root._ddcQueue.length === 0)
            return;
        const connector = root._ddcQueue[0];
        ddcGetvcpProc.connector = connector;
        ddcGetvcpProc.command = ["ddcutil", "--bus", root._ddcBuses[connector], "--skip-ddc-checks", "getvcp", "10", "--brief"];
        ddcGetvcpProc.running = true;
    }

    // Re-polls the device list. Load-bearing for the OSD (M5 Task 6): a
    // brightness keybind runs `brightnessctl set 5%+` itself (bypassing
    // set()/step() below) before calling the `osd brightness` IPC route, so
    // this service's cached percent is stale by exactly one step until
    // something re-reads it, no polling loop means that has to be explicit.
    function refresh() {
        listProc.running = true;
    }

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

    Process {
        id: ddcDetectProc
        command: ["ddcutil", "--skip-ddc-checks", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: root._applyDetect(text)
        }
        onExited: exitCode => {
            if (exitCode === 127) {
                root._ddcBuses = ({});
                root._ddcQueue = [];
                root._clearDdcRows();
            }
        }
    }

    // Reused sequentially across `_ddcQueue` (one bus at a time, ddcutil
    // is slow enough that running several in parallel would just contend
    // on the same I2C bus anyway).
    Process {
        id: ddcGetvcpProc
        property string connector: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root._ddcQueue = root._ddcQueue.slice(1);
                const m = /VCP\s+10\s+C\s+(\d+)\s+(\d+)/.exec(text);
                if (m) {
                    const current = parseInt(m[1], 10);
                    const max = parseInt(m[2], 10);
                    const pct = max > 0 ? Math.round(current * 100 / max) : 0;
                    root.devices.append({ deviceId: ddcGetvcpProc.connector, label: ddcGetvcpProc.connector, percent: pct, max: max });
                }
                root._pumpDdcQueue();
            }
        }
    }

    Process {
        id: ddcSetvcpProc
    }
}
