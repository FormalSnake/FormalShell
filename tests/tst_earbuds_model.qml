import QtQuick
import QtTest
import "../shell/Earbuds/model.js" as Model

TestCase {
    name: "EarbudsModel"

    function buds(key, connected, batteries) {
        return Model.device({ key: key, backend: "test", name: key, connected: connected, batteries: batteries || [] });
    }

    function test_device_fills_defaults() {
        var d = Model.device({ key: "k", backend: "b" });
        compare(d.kind, "earbuds");
        compare(d.connected, false);
        compare(d.batteries.length, 0);
        compare(d.controls.length, 0);
        compare(d.stateLine, "");
        compare(Model.device({ key: "k", backend: "b", kind: "headphone" }).kind, "headphone");
    }

    function test_battery_hints() {
        var d = buds("a", true, [
            { id: "left", label: "Left", level: 50, charging: true, inEar: true },
            { id: "case", label: "Case", level: 90, charging: false, inEar: null }
        ]);
        var rows = Model.batteryRows(d);
        compare(rows[0].hint, "In ear / Charging");
        compare(rows[1].hint, "");
        compare(Model.batteryRows(null).length, 0);
    }

    function test_worst_level_leaves_the_case_out() {
        compare(Model.worstLevel(buds("a", true, [
            { id: "left", level: 70 }, { id: "right", level: 30 }, { id: "case", level: 5 }
        ])), 30);
        compare(Model.worstLevel(buds("a", true, [{ id: "single", level: 64 }])), 64);
        compare(Model.worstLevel(buds("a", true, [{ id: "case", level: 5 }])), -1);
        compare(Model.worstLevel(null), -1);
    }

    function test_battery_summary() {
        compare(Model.batterySummary(buds("a", true, [
            { id: "left", level: 70 }, { id: "right", level: 30 }, { id: "case", level: 5 }
        ])), "L 70 / R 30 / CASE 5");
        compare(Model.batterySummary(buds("a", true, [{ id: "single", level: 64 }])), "64");
    }

    function test_sections_keep_first_appearance_order() {
        var d = Model.device({ key: "k", backend: "b", controls: [
            Model.choice("anc", "Noise", "Listening mode", "on", []),
            Model.toggle("lowLatency", "Low latency", "", "Options", false),
            Model.range("level", "Level", "Listening mode", 2, 0, 3, 1)
        ] });
        var s = Model.sections(d);
        compare(s.map(function (x) { return x.section; }).join(","), "Listening mode,Options");
        compare(s[0].controls.map(function (c) { return c.key; }).join(","), "anc,level");
    }

    function test_coerce() {
        var ch = Model.choice("anc", "Noise", "S", "off", [{ value: "off" }, { value: "on" }]);
        compare(Model.coerce(ch, "on"), "on");
        compare(Model.coerce(ch, "max"), undefined);
        compare(Model.optionIndex(ch), 0);

        var t = Model.toggle("t", "T", "", "S", false);
        compare(Model.coerce(t, "on"), true);
        compare(Model.coerce(t, false), false);
        compare(Model.coerce(t, "maybe"), undefined);

        var r = Model.range("r", "R", "S", 40, 0, 100, 5);
        compare(Model.coerce(r, "42"), 42);
        compare(Model.coerce(r, 42.6), 43);
        compare(Model.coerce(r, 250), 100);
        compare(Model.coerce(r, -3), 0);
        compare(Model.coerce(r, ""), undefined);
        compare(Model.coerce(r, "loud"), undefined);
        compare(Model.rangePercent(r), 40);
        compare(Model.rangePercent(Model.range("r", "R", "S", 2, 0, 4, 1)), 50);
    }

    function test_pick_active() {
        var a = buds("a", false), b = buds("b", true), c = buds("c", true);
        compare(Model.pickActive([], "a"), null);
        compare(Model.pickActive([a, b, c], "c").key, "c");
        compare(Model.pickActive([a, b, c], "gone").key, "b");
        compare(Model.pickActive([a], "").key, "a");
    }

    function test_range_readout_and_fill() {
        var pct = Model.range("adaptive", "Adaptive noise", "S", 40, 0, 100, 5);
        compare(pct.unit, "percent");
        compare(Model.rangeText(pct), "40%");
        compare(Model.rangeFraction(pct), 0.4);

        var band = function (v) { return Model.range("eq-bass", "Bass", "S", v, -6, 6, 1, "db"); };
        compare(Model.rangeText(band(5)), "+5\u00a0dB");
        compare(Model.rangeText(band(0)), "0\u00a0dB");
        compare(Model.rangeText(band(-2)), "-2\u00a0dB");
        compare(Model.rangeText(band(-0.4)), "0\u00a0dB");
        compare(Model.rangeFraction(band(-6)), 0);
        compare(Model.rangeFraction(band(0)), 0.5);
        compare(Model.rangeFraction(band(6)), 1);
        compare(Model.rangeFraction(band(-3)), 0.25);
        compare(Model.choice("c", "C", "S", null, []).unit, "");
    }

    function test_bluetooth_devices_and_the_smoke_override() {
        var live = [{ address: "aa:bb:cc:dd:ee:ff", name: "Buds", deviceName: "Buds", connected: true }];
        compare(Model.bluetoothDevices(live, "")[0].address, "AA:BB:CC:DD:EE:FF");
        compare(Model.bluetoothDevices([], "").length, 0);
        compare(Model.bluetoothDevices(live, "not json")[0].name, "Buds");
        var o = Model.bluetoothDevices(live, "[{\"address\":\"ac:12:2f:11:22:33\",\"name\":\"Liberty\",\"connected\":true},{\"name\":\"no address\"}]");
        compare(o.length, 1);
        compare(o[0].address, "AC:12:2F:11:22:33");
        compare(o[0].deviceName, "Liberty");
        compare(o[0].connected, true);
    }
}
