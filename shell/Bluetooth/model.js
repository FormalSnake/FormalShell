.pragma library

// Pure model for the bluetooth panel's device buckets (M14 Task 1): which
// devices render, in which bucket, sorted how, and their status line. No
// Quickshell access, so it's testable head-on (mirrors workspaces.js).
// Reimplemented from omarchy's Model.js deviceLists()/hasHumanName()
// (~/Developer/omarchy/shell/plugins/panels/bluetooth/Model.js) against
// Quickshell.Bluetooth's native BluetoothDevice properties (paired/bonded/
// trusted/connected/pairing/state/battery/batteryAvailable —
// src/bluetooth/device.hpp) instead of bluetoothctl output.

// BluetoothDeviceState (src/bluetooth/device.hpp:14-29).
var DeviceState = {
    Disconnected: 0,
    Connected: 1,
    Disconnecting: 2,
    Connecting: 3
};

function isMacShaped(name) {
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(name);
}

function isUuidShaped(name) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(name)
        || /^[0-9a-f]{32}$/i.test(name);
}

// Rejects the empty string and the two label shapes BlueZ falls back to
// when a device hasn't advertised a real name yet — a raw address or a
// service UUID, neither of which is worth showing a person.
function hasHumanName(name) {
    var label = String(name || "").trim();
    if (label === "") return false;
    if (isMacShaped(label)) return false;
    if (isUuidShaped(label)) return false;
    return true;
}

function _label(device) {
    return device.name || device.deviceName || "";
}

function _sortByLabel(devices) {
    return devices.slice().sort(function (a, b) {
        return _label(a).localeCompare(_label(b));
    });
}

// known = paired||bonded||trusted (omarchy's rule); available devices only
// surface while `discovering` is true — a raw scan result the adapter
// hasn't paired/trusted has no business staying listed once scanning
// stops. Devices without a human-readable name are dropped from every
// bucket, connected or not.
function buckets(devices, discovering) {
    // `devices` arrives either as a plain JS array (tests) or as QML's
    // sequence wrapper over QList<QObject*> (adapter.devices.values fed
    // straight in by BluetoothPanel) — and Array.isArray is FALSE for the
    // wrapper, which made this guard discard every real device on the
    // live host (2026-08-04) while fixture-fed tests stayed green. Copy
    // via indexed loop, the one protocol both shapes share.
    var list = [];
    if (devices && devices.length !== undefined)
        for (var c = 0; c < devices.length; c++) list.push(devices[c]);
    var connected = [];
    var known = [];
    var available = [];

    for (var i = 0; i < list.length; i++) {
        var d = list[i];
        if (!d || !hasHumanName(_label(d))) continue;
        if (d.connected) connected.push(d);
        else if (d.paired || d.bonded || d.trusted) known.push(d);
        else if (discovering) available.push(d);
    }

    return {
        connected: _sortByLabel(connected),
        known: _sortByLabel(known),
        available: _sortByLabel(available)
    };
}

// The row's own state line, words only (DESIGN.md §1 "Type"): what BlueZ
// is doing to this device right now, or "" when it is doing nothing.
function activityText(device) {
    if (!device) return "";
    if (device.pairing === true) return "PAIRING…";
    if (device.state === DeviceState.Connecting) return "CONNECTING…";
    return "";
}

// The row's trailing value. Only an already-connected device that reports
// a battery has one, and `battery` is a 0..1 fraction (CLAUDE.md's
// quickshell percentage rule), so the conversion happens here once.
function batteryText(device) {
    if (!device || !device.connected || !device.batteryAvailable) return "";
    return Math.round(device.battery * 100) + "%";
}
