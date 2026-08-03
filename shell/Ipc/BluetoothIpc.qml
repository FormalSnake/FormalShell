import Quickshell.Bluetooth
import Quickshell.Io

// `qs ipc call bluetooth toggle|power <on|off>|status` — spec addendum
// (M16 Task 10, the `panel`/`nightlight` tradition, CLAUDE.md hard rules):
// omarchy f54edbe parity (toggleBluetooth), radio control for compositor
// keybinds and the smoke rig. Bound directly to Quickshell.Bluetooth, same
// as BluetoothPanel.qml — no panel reference needed, unlike network's
// SSID-keyed verbs. No adapter -> honest "error: no bluetooth adapter",
// never a silent no-op; status() stays a JSON reply either way so a poller
// never has to special-case the no-adapter case as a wire error.
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

    function status(): string {
        var adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return JSON.stringify({ available: false, enabled: false, connected: 0 });
        var devices = adapter.devices.values;
        var connected = 0;
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].connected)
                connected++;
        }
        return JSON.stringify({ available: true, enabled: adapter.enabled, connected: connected });
    }
}
