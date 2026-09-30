import QtQuick
import QtTest
import "../shell/Earbuds/airpods.js" as Airpods
import "../shell/Earbuds/model.js" as Model

TestCase {
    name: "EarbudsAirpods"

    // Fixture lines: one-line, sorted-key JSON, exactly the shape the
    // librepods daemon writes to status.json (schema table in
    // docs/superpowers/plans/2026-08-18-m29-device-panels.md).

    property string fixturePro3: "{\"adaptive_noise_level\":40,\"case\":{\"available\":true,\"charging\":false,\"level\":80},\"connected\":true,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":85},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":3,\"one_bud_anc_mode\":true,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":90},\"schema_version\":1,\"supports_noise_off\":false}"

    property string fixtureNonPro: "{\"adaptive_noise_level\":0,\"case\":{\"available\":true,\"charging\":true,\"level\":55},\"connected\":true,\"conversational_awareness\":false,\"device_name\":\"AirPods\",\"ear_detection_behavior\":1,\"is_pro_series\":false,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":false,\"level\":60},\"lid_state\":0,\"model_int\":2,\"model_name\":\"AirPods (3rd generation)\",\"model_number\":\"A2564\",\"noise_mode\":1,\"one_bud_anc_mode\":false,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":58},\"schema_version\":1,\"supports_noise_off\":true}"

    property string fixtureFreshDaemon: "{\"adaptive_noise_level\":0,\"connected\":false,\"conversational_awareness\":false,\"device_name\":\"\",\"ear_detection_behavior\":0,\"is_pro_series\":false,\"lid_state\":2,\"model_int\":0,\"model_name\":\"\",\"model_number\":\"\",\"noise_mode\":-1,\"one_bud_anc_mode\":false,\"schema_version\":1,\"supports_noise_off\":true}"

    property string fixtureInCase: "{\"adaptive_noise_level\":0,\"case\":{\"available\":true,\"charging\":true,\"level\":45},\"connected\":false,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":true,\"in_ear\":false,\"level\":72},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":-1,\"one_bud_anc_mode\":false,\"right\":{\"available\":true,\"charging\":true,\"in_ear\":false,\"level\":71},\"schema_version\":1,\"supports_noise_off\":false}"

    property string fixtureWrongSchema: "{\"adaptive_noise_level\":40,\"case\":{\"available\":true,\"charging\":false,\"level\":80},\"connected\":true,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":85},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":3,\"one_bud_anc_mode\":true,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":90},\"schema_version\":2,\"supports_noise_off\":false}"

    function keys(list, field) {
        return list.map(function (x) { return x[field]; }).join(",");
    }

    function device(text) {
        var devs = Airpods.normalise(Airpods.parseStatus(text));
        compare(devs.length, 1);
        return devs[0];
    }

    function test_pro3_full_status() {
        var s = Airpods.parseStatus(fixturePro3);
        compare(s.ok, true);
        compare(s.isPro, true);
        compare(s.supportsOff, false);
        compare(s.noiseMode, 3);

        var d = device(fixturePro3);
        compare(d.key, "airpods");
        compare(d.backend, "airpods");
        compare(d.name, "Kyan's AirPods Pro");
        compare(d.connected, true);
        compare(d.stateLine, "Adaptive / Lid closed");

        var rows = Model.batteryRows(d);
        compare(keys(rows, "key"), "left,right,case");
        compare(rows[0].level, 85);
        compare(rows[0].hint, "In ear");
        compare(rows[2].hint, "");
        compare(Model.worstLevel(d), 85);

        compare(keys(d.controls, "key"), "noise,adaptive,ca,onebud,ear");
        compare(keys(Model.sections(d), "section"), "Listening mode,Options,Ear detection");

        var noise = Model.control(d, "noise");
        compare(noise.kind, "choice");
        compare(keys(noise.options, "value"), "anc,transparency,adaptive");
        compare(keys(noise.options, "icon"), "ear-off,ear,audio-waveform");
        compare(noise.value, "adaptive");

        var adaptive = Model.control(d, "adaptive");
        compare(adaptive.kind, "range");
        compare(adaptive.value, 40);
        compare(adaptive.step, 5);

        compare(Model.control(d, "ca").value, true);
        compare(Model.control(d, "ca").hint, "Lowers volume when you talk");
        compare(Model.control(d, "onebud").value, true);
        compare(Model.control(d, "ear").value, "one");
    }

    function test_nonpro_status_filters_adaptive_and_keeps_off() {
        var d = device(fixtureNonPro);
        var noise = Model.control(d, "noise");
        compare(keys(noise.options, "value"), "off,anc,transparency");
        compare(noise.value, "anc");
        compare(Model.control(d, "adaptive"), null);
        compare(Model.control(d, "ca"), null);
        compare(Model.control(d, "onebud"), null);
        compare(Model.control(d, "ear").value, "both");
        compare(keys(Model.sections(d), "section"), "Listening mode,Ear detection");

        compare(Model.batteryRows(d)[1].hint, "In ear");
        compare(d.stateLine, "Noise cancellation / Lid open");
    }

    function test_adaptive_level_only_in_adaptive_mode() {
        var d = device(fixturePro3.replace("\"noise_mode\":3", "\"noise_mode\":1"));
        compare(Model.control(d, "noise").value, "anc");
        compare(Model.control(d, "adaptive"), null);
    }

    function test_fresh_daemon_knows_no_device() {
        var s = Airpods.parseStatus(fixtureFreshDaemon);
        compare(s.ok, true);
        compare(s.left.available, false);
        compare(s.left.level, -1);
        compare(Airpods.normalise(s).length, 0);
    }

    function test_in_case_keeps_battery_and_ear_detection_only() {
        var d = device(fixtureInCase);
        compare(d.connected, false);
        compare(keys(Model.batteryRows(d), "key"), "left,right,case");
        compare(Model.batteryRows(d)[0].hint, "Charging");
        compare(Model.batteryRows(d)[2].hint, "Charging");
        compare(keys(d.controls, "key"), "ear");
        compare(d.stateLine, "Not connected / Lid closed");
    }

    function test_wrong_schema_version_returns_default_shape() {
        var s = Airpods.parseStatus(fixtureWrongSchema);
        compare(s.ok, false);
        compare(s.deviceName, "");
        compare(Airpods.normalise(s).length, 0);
    }

    function test_malformed_json_returns_default_shape() {
        var s = Airpods.parseStatus("{not json at all");
        compare(s.ok, false);
        compare(s.left.available, false);
        compare(Airpods.normalise(s).length, 0);
    }

    function test_empty_text_returns_default_shape() {
        var s = Airpods.parseStatus("");
        compare(s.ok, false);
        compare(s.supportsOff, true);
        compare(s.lidState, 2);
    }

    function test_lid_and_noise_mode_labels() {
        compare(Airpods.lidLabel(0), "Lid open");
        compare(Airpods.lidLabel(1), "Lid closed");
        compare(Airpods.lidLabel(2), "");
        compare(Airpods.noiseModeLabel(0), "Off");
        compare(Airpods.noiseModeLabel(1), "Noise cancellation");
        compare(Airpods.noiseModeLabel(2), "Transparency");
        compare(Airpods.noiseModeLabel(3), "Adaptive");
        compare(Airpods.noiseModeLabel(-1), "Unknown");
    }

    // The daemon socket's verbs, and nothing outside them.
    function test_command_allow_list() {
        compare(Airpods.command("noise", "anc"), "noise:anc");
        compare(Airpods.command("noise", "adaptive"), "noise:adaptive");
        compare(Airpods.command("noise", "loud"), "");
        compare(Airpods.command("adaptive", 40), "adaptive:40");
        compare(Airpods.command("adaptive", 101), "");
        compare(Airpods.command("adaptive", "40"), "");
        compare(Airpods.command("ca", true), "ca:on");
        compare(Airpods.command("ca", false), "ca:off");
        compare(Airpods.command("onebud", true), "onebud:on");
        compare(Airpods.command("ear", "both"), "ear:both");
        compare(Airpods.command("ear", "never"), "");
        compare(Airpods.command("connect", true), "");
        compare(Airpods.command("forget", ""), "");
    }

    // What an IPC string becomes before it reaches command().
    function test_ipc_strings_coerce_into_commands() {
        var d = device(fixturePro3);
        compare(Airpods.command("ca", Model.coerce(Model.control(d, "ca"), "off")), "ca:off");
        compare(Airpods.command("adaptive", Model.coerce(Model.control(d, "adaptive"), "42")), "adaptive:42");
        compare(Airpods.command("noise", Model.coerce(Model.control(d, "noise"), "transparency")), "noise:transparency");
        compare(Model.coerce(Model.control(d, "noise"), "off"), undefined);
    }
}
