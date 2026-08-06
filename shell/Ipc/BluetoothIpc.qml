import Quickshell.Bluetooth
import Quickshell.Io

// `qs ipc call bluetooth toggle|power <on|off>|status|trust <address>|untrust
// <address>` — spec addendum (M16 Task 10, the `panel`/`nightlight`
// tradition, CLAUDE.md hard rules): omarchy f54edbe parity (toggleBluetooth),
// radio control for compositor keybinds and the smoke rig. Bound directly to
// Quickshell.Bluetooth, same as BluetoothPanel.qml — no panel reference
// needed, unlike network's SSID-keyed verbs. No adapter -> honest
// "error: no bluetooth adapter", never a silent no-op; status() stays a JSON
// reply either way so a poller never has to special-case the no-adapter case
// as a wire error.
//
// trust/untrust are the headless path for BluetoothPanel's own TRUSTED
// toggle. They write BluetoothDevice.trusted (a real WRITE property, pinned
// quickshell source src/bluetooth/device.hpp:92) directly rather than
// routing through the panel, which this handler holds no reference to by the
// design above — so, unlike NetworkIpc's connect/forget, they never arm the
// panel's in-flight row state, and "ok" here means the property write was
// issued, exactly as it already does for `power`. An address no device on the
// adapter answers to, or one BlueZ has not paired, is an error string.
//
// `status()`'s `devices[].trusted` is NOT proof the write reached BlueZ, and
// no smoke assertion may treat it as such: quickshell stores the requested
// value locally and emits trustedChanged before it pushes the D-Bus Set, and
// never rolls back a Set that BlueZ rejects (device.cpp:64-68,
// properties.cpp:268-297), so this field reports what was ASKED FOR whenever
// the two disagree. `bluetoothctl info <address>`'s own `Trusted:` line is the
// only real read-back — BluetoothPanel's trust flow settles against exactly
// that, and a headless check wanting ground truth must call it too.
IpcHandler {
    target: "bluetooth"

    function toggle(): string {
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return "error: no bluetooth adapter";
        adapter.enabled = !adapter.enabled;
        return "ok";
    }

    function power(state: string): string {
        if (state !== "on" && state !== "off")
            return "error: power state must be 'on' or 'off'";
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return "error: no bluetooth adapter";
        adapter.enabled = state === "on";
        return "ok";
    }

    // BlueZ hands addresses out uppercase; matching case-insensitively means
    // a keybind or smoke script can paste one back in whatever case it has.
    function _findDevice(address) {
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return null;
        var devices = adapter.devices.values;
        var wanted = String(address || "").toUpperCase();
        for (var i = 0; i < devices.length; i++) {
            if (String(devices[i].address || "").toUpperCase() === wanted)
                return devices[i];
        }
        return null;
    }

    function _writeTrust(address, want) {
        if (!Bluetooth.defaultAdapter)
            return "error: no bluetooth adapter";
        var device = _findDevice(address);
        if (!device)
            return "error: unknown device '" + address + "'";
        if (!device.paired)
            return "error: device '" + address + "' is not paired";
        device.trusted = want;
        return "ok";
    }

    function trust(address: string): string {
        return _writeTrust(address, true);
    }

    function untrust(address: string): string {
        return _writeTrust(address, false);
    }

    // `devices` is additive to the original {available, enabled, connected}
    // shape — a poller reading only the counters is unaffected — and carries
    // the same facts the panel's rows render, so trust/untrust above have a
    // read-back and the smoke rig has something to assert.
    function status(): string {
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return JSON.stringify({ available: false, enabled: false, connected: 0, devices: [] });
        var devices = adapter.devices.values;
        var connected = 0;
        var rows = [];
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].connected)
                connected++;
            rows.push({
                address: devices[i].address,
                name: devices[i].name || devices[i].deviceName,
                paired: devices[i].paired,
                trusted: devices[i].trusted,
                connected: devices[i].connected
            });
        }
        return JSON.stringify({ available: true, enabled: adapter.enabled, connected: connected, devices: rows });
    }
}
