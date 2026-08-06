import QtQuick
import QtTest
import "../shell/Bluetooth/model.js" as BluetoothModel

TestCase {
    name: "BluetoothModel"

    function dev(name, flags) {
        flags = flags || {};
        return {
            name: name,
            connected: flags.connected === true,
            paired: flags.paired === true,
            bonded: flags.bonded === true,
            trusted: flags.trusted === true,
            pairing: flags.pairing === true,
            state: flags.state !== undefined ? flags.state : BluetoothModel.DeviceState.Disconnected,
            battery: flags.battery !== undefined ? flags.battery : 0,
            batteryAvailable: flags.batteryAvailable === true
        };
    }

    function names(devices) {
        return devices.map(function (d) { return d.name; }).join(",");
    }

    function test_hasHumanName_rejects_empty_mac_and_uuid() {
        compare(BluetoothModel.hasHumanName(""), false);
        compare(BluetoothModel.hasHumanName("   "), false);
        compare(BluetoothModel.hasHumanName("AA:BB:CC:DD:EE:FF"), false);
        compare(BluetoothModel.hasHumanName("aa-bb-cc-dd-ee-ff"), false);
        compare(BluetoothModel.hasHumanName("4c55a1e0-b100-4ac3-a2fc-2f2e1234abcd"), false);
        compare(BluetoothModel.hasHumanName("4c55a1e0b1004ac3a2fc2f2e1234abcd"), false);
        compare(BluetoothModel.hasHumanName("Sony WH-1000XM4"), true);
    }

    function test_buckets_accepts_sequence_shaped_list_not_just_arrays() {
        // QML feeds buckets() adapter.devices.values — a Qt sequence
        // wrapper, NOT a JS Array (Array.isArray === false). An
        // array-like with length+indices mimics that shape; devices must
        // classify, not vanish (the 2026-08-04 live-host regression).
        var seq = { length: 2 };
        seq[0] = dev("AirPods Pro", { connected: true, paired: true, bonded: true, trusted: true });
        seq[1] = dev("MX Master 3S M", { connected: true, paired: true, bonded: true, trusted: true });
        var b = BluetoothModel.buckets(seq, false);
        compare(names(b.connected), "AirPods Pro,MX Master 3S M");
        compare(b.known.length, 0);
        compare(b.available.length, 0);
    }

    function test_buckets_splits_connected_known_available_while_discovering() {
        var devices = [
            dev("Zeta", { connected: true, paired: true }),
            dev("Alpha", { paired: true }),
            dev("Beta", { trusted: true }),
            dev("Gamma", {}),
            dev("AA:BB:CC:DD:EE:FF", {})
        ];
        var b = BluetoothModel.buckets(devices, true);
        compare(names(b.connected), "Zeta");
        compare(names(b.known), "Alpha,Beta");
        compare(names(b.available), "Gamma");
    }

    function test_buckets_hides_available_when_not_discovering() {
        var devices = [dev("Zeta", { connected: true }), dev("Gamma", {})];
        var b = BluetoothModel.buckets(devices, false);
        compare(b.connected.length, 1);
        compare(b.available.length, 0);
    }

    function test_buckets_filters_unnamed_devices_from_every_bucket() {
        var devices = [
            dev("AA:BB:CC:DD:EE:FF", { connected: true }),
            dev("", { paired: true })
        ];
        var b = BluetoothModel.buckets(devices, true);
        compare(b.connected.length, 0);
        compare(b.known.length, 0);
    }

    function test_buckets_sorts_alphabetically_within_bucket() {
        var devices = [
            dev("Zeta", { paired: true }),
            dev("Alpha", { paired: true }),
            dev("Mid", { paired: true })
        ];
        var b = BluetoothModel.buckets(devices, false);
        compare(names(b.known), "Alpha,Mid,Zeta");
    }

    function test_statusText_pairing_beats_everything() {
        compare(BluetoothModel.statusText(dev("A", { pairing: true, connected: true, batteryAvailable: true, battery: 0.9 })), "PAIRING…");
    }

    function test_statusText_connecting_state() {
        compare(BluetoothModel.statusText(dev("A", { state: BluetoothModel.DeviceState.Connecting })), "CONNECTING…");
    }

    function test_statusText_battery_percent_when_connected() {
        compare(BluetoothModel.statusText(dev("A", { connected: true, batteryAvailable: true, battery: 0.42 })), "42%");
    }

    function test_statusText_blank_when_connected_without_battery() {
        compare(BluetoothModel.statusText(dev("A", { connected: true, batteryAvailable: false })), "");
    }

    function test_statusText_blank_for_null_device() {
        compare(BluetoothModel.statusText(null), "");
    }

    function test_hasConnectedAirpods_name_contains_case_insensitive() {
        verify(BluetoothModel.hasConnectedAirpods([dev("Kyan's AirPods Pro", { connected: true })]));
        verify(BluetoothModel.hasConnectedAirpods([dev("airpods max", { connected: true })]));
    }

    function test_hasConnectedAirpods_false_for_other_devices() {
        verify(!BluetoothModel.hasConnectedAirpods([dev("WH-1000XM5", { connected: true }), dev("Keychron K2", { connected: true })]));
        verify(!BluetoothModel.hasConnectedAirpods([]));
        verify(!BluetoothModel.hasConnectedAirpods(undefined));
    }
}
