import QtQuick
import QtTest
import "../shell/Earbuds/samsung.js" as Samsung
import "../shell/Earbuds/model.js" as Model

TestCase {
    name: "EarbudsSamsung"

    // LiveBudsCli's `earbuds status -o json` prints the daemon's response
    // verbatim (src/cmd/info.rs), one JSON line: Response<BudsInfoInner> in
    // src/daemon/unix_socket/mod.rs, its payload field order and names from
    // BudsInfoInner in src/daemon/buds_info.rs, the error form from get_err
    // in request_handler.rs (all at commit 37f27b5). scripts/polybar.sh in
    // the same repo reads .payload.batt_left / .placement_left off this
    // shape. No daemon or buds run here, so the values are hand-written to
    // that shape; Model is serde's plain variant name, the number fields the
    // wire values of galaxy_buds_rs 0.2.11's Placement and EqualizerType.

    function payload(model, extra) {
        var p = {
            address: "AA:BB:CC:11:22:33",
            ready: true,
            batt_left: 82,
            batt_right: 77,
            batt_case: 60,
            placement_left: 1,
            placement_right: 1,
            equalizer_type: 1,
            touchpads_blocked: false,
            noise_reduction: false,
            did_battery_notify: false,
            touchpad_option_left: 2,
            touchpad_option_right: 2,
            paused_music_earlier: false,
            debug: { voltage_left: 4.1, voltage_right: 4.1, temperature_left: 24.5, temperature_right: 24.5, current_left: 0.001, current_right: 0.001 },
            model: model,
            ambient_sound_enabled: false,
            ambient_sound_volume: 0,
            extra_high_ambient_volume: false,
            tab_lock_status: { touch_an_hold_on: true, triple_tap_on: true, double_tap_on: true, tap_on: true, touch_controls_on: true }
        };
        for (var k in extra)
            p[k] = extra[k];
        return JSON.stringify({ status: "success", device: "AA:BB:CC:11:22:33", status_message: null, payload: p });
    }

    property string errorLine: "{\"status\":\"error\",\"device\":\"\",\"status_message\":\"No connected device found\",\"payload\":null}"

    function keys(list, field) {
        return list.map(function (x) { return x[field]; }).join(",");
    }

    function device(text, name) {
        var devs = Samsung.normalise(Samsung.parseStatus(text), name || "");
        compare(devs.length, 1);
        return devs[0];
    }

    function bt(address, name, deviceName, connected) {
        return { address: address, name: name, deviceName: deviceName, connected: connected };
    }

    function test_buds2_has_anc_and_ambient() {
        var d = device(payload("Buds2", { noise_reduction: true, equalizer_type: 3 }), "Kyan's Buds2");
        compare(d.key, "samsung:AA:BB:CC:11:22:33");
        compare(d.backend, "samsung");
        compare(d.name, "Kyan's Buds2");
        compare(d.stateLine, "Noise cancellation");
        compare(keys(Model.batteryRows(d), "key"), "left,right");
        compare(keys(d.controls, "key"), "anc,ambient,eq");
        compare(keys(Model.sections(d), "section"), "Listening mode,Equalizer");
        compare(Model.control(d, "anc").kind, "toggle");
        compare(Model.control(d, "anc").value, true);
        var ambient = Model.control(d, "ambient");
        compare(keys(ambient.options, "value"), "0,1,2,3");
        compare(keys(ambient.options, "label"), "Off,1,2,3");
        compare(ambient.value, 0);
        compare(Model.control(d, "eq").value, "dynamic");
        compare(keys(Model.control(d, "eq").options, "value"), "normal,bass,soft,dynamic,clear,treble");
    }

    function test_buds_plus_ambient_only_with_extra_high() {
        var d = device(payload("BudsPlus", { ambient_sound_enabled: true, ambient_sound_volume: 3, extra_high_ambient_volume: true }));
        compare(d.name, "Galaxy Buds+");
        compare(keys(d.controls, "key"), "ambient,eq");
        compare(keys(Model.control(d, "ambient").options, "value"), "0,1,2,3,4");
        compare(Model.control(d, "ambient").value, 4);
        compare(d.stateLine, "Ambient sound");
    }

    function test_buds_pro_has_anc_only() {
        var d = device(payload("BudsPro"));
        compare(keys(d.controls, "key"), "anc,eq");
        compare(Model.control(d, "anc").value, false);
        compare(d.stateLine, "Off");
    }

    function test_unlisted_model_gets_no_listening_controls() {
        var d = device(payload("SomethingNew"));
        compare(keys(d.controls, "key"), "eq");
        compare(d.stateLine, "");
        compare(Samsung.normalise(Samsung.parseStatus(payload("constructor")), "").length, 1);
    }

    function test_batteries_placement_and_case() {
        var out = device(payload("Buds2", { placement_left: 2, placement_right: 2, batt_case: 60 }));
        compare(keys(Model.batteryRows(out), "key"), "left,right");
        compare(Model.batteryRows(out)[0].hint, "");
        var mixed = device(payload("Buds2", { placement_left: 3, placement_right: 1 }));
        var rows = Model.batteryRows(mixed);
        compare(keys(rows, "key"), "left,right,case");
        compare(rows[0].hint, "Charging");
        compare(rows[1].hint, "In ear");
        compare(rows[2].level, 60);
        compare(Model.worstLevel(mixed), 77);
    }

    function test_undetected_equalizer_lights_nothing() {
        compare(Model.control(device(payload("Buds2", { equalizer_type: 9 })), "eq").value, null);
    }

    function test_not_ready_or_error_lists_nothing() {
        compare(Samsung.normalise(Samsung.parseStatus(payload("Buds2", { ready: false })), "").length, 0);
        var e = Samsung.parseStatus(errorLine);
        compare(e.ok, false);
        compare(e.message, "No connected device found");
        compare(Samsung.normalise(e, "").length, 0);
        compare(Samsung.parseStatus("").ok, false);
        compare(Samsung.parseStatus("Could not connect to daemon").ok, false);
        compare(Samsung.parseStatus("{not json").ok, false);
    }

    function test_leading_daemon_banner_is_skipped() {
        var s = Samsung.parseStatus("Daemon started successfully\n" + payload("Buds2"));
        compare(s.ok, true);
        compare(s.model, "Buds2");
    }

    function test_connected_galaxy_buds_only() {
        var found = Samsung.connectedBuds([
            bt("aa:bb:cc:11:22:33", "My buds", "Galaxy Buds2 Pro (1234)", true),
            bt("AA:BB:CC:44:55:66", "Galaxy Buds Live (ABCD)", "Galaxy Buds Live (ABCD)", false),
            bt("AA:BB:CC:77:88:99", "WH-1000XM5", "WH-1000XM5", true),
            bt("AA:BB:CC:00:00:01", "Galaxy Buds+ (9F2A)", "", true)
        ]);
        compare(keys(found, "address"), "AA:BB:CC:11:22:33,AA:BB:CC:00:00:01");
        compare(found[0].name, "My buds");
        compare(Samsung.connectedBuds([]).length, 0);
    }

    function test_command_allow_list() {
        compare(Samsung.command("anc", true).join(" "), "enable anc");
        compare(Samsung.command("anc", false).join(" "), "disable anc");
        compare(Samsung.command("anc", "on").length, 0);
        compare(Samsung.command("ambient", 2).join(" "), "set ambientsound 2");
        compare(Samsung.command("ambient", 0).join(" "), "set ambientsound 0");
        compare(Samsung.command("ambient", 5).length, 0);
        compare(Samsung.command("ambient", 1.5).length, 0);
        compare(Samsung.command("ambient", "2").length, 0);
        compare(Samsung.command("eq", "bass").join(" "), "set equalizer bass");
        compare(Samsung.command("eq", "bass; reboot").length, 0);
        compare(Samsung.command("touchpad", true).length, 0);
    }

    function test_argv_builders() {
        compare(Samsung.statusArgv("AA:BB:CC:11:22:33").join(" "), "earbuds -q -s AA:BB:CC:11:22:33 status -o json");
        compare(Samsung.argv("AA:BB:CC:11:22:33", ["set", "equalizer", "soft"]).join(" "), "earbuds -q -s AA:BB:CC:11:22:33 set equalizer soft");
        compare(Samsung.argv("--daemon", ["status"]).length, 0);
    }
}
