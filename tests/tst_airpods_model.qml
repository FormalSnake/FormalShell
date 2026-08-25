import QtQuick
import QtTest
import "../shell/Airpods/model.js" as AirpodsModel

TestCase {
    name: "AirpodsModel"

    // Fixture lines: one-line, sorted-key JSON, exactly the shape the
    // librepods daemon writes to status.json (schema table in
    // docs/superpowers/plans/2026-08-18-m29-device-panels.md).

    property string fixturePro3: "{\"adaptive_noise_level\":40,\"case\":{\"available\":true,\"charging\":false,\"level\":80},\"connected\":true,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":85},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":3,\"one_bud_anc_mode\":true,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":90},\"schema_version\":1,\"supports_noise_off\":false}"

    property string fixtureNonPro: "{\"adaptive_noise_level\":0,\"case\":{\"available\":true,\"charging\":true,\"level\":55},\"connected\":true,\"conversational_awareness\":false,\"device_name\":\"AirPods\",\"ear_detection_behavior\":1,\"is_pro_series\":false,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":false,\"level\":60},\"lid_state\":0,\"model_int\":2,\"model_name\":\"AirPods (3rd generation)\",\"model_number\":\"A2564\",\"noise_mode\":1,\"one_bud_anc_mode\":false,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":58},\"schema_version\":1,\"supports_noise_off\":true}"

    property string fixtureFreshDaemon: "{\"adaptive_noise_level\":0,\"connected\":false,\"conversational_awareness\":false,\"device_name\":\"\",\"ear_detection_behavior\":0,\"is_pro_series\":false,\"lid_state\":2,\"model_int\":0,\"model_name\":\"\",\"model_number\":\"\",\"noise_mode\":-1,\"one_bud_anc_mode\":false,\"schema_version\":1,\"supports_noise_off\":true}"

    property string fixtureInCase: "{\"adaptive_noise_level\":0,\"case\":{\"available\":true,\"charging\":true,\"level\":45},\"connected\":false,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":true,\"in_ear\":false,\"level\":72},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":-1,\"one_bud_anc_mode\":false,\"right\":{\"available\":true,\"charging\":true,\"in_ear\":false,\"level\":71},\"schema_version\":1,\"supports_noise_off\":false}"

    property string fixtureWrongSchema: "{\"adaptive_noise_level\":40,\"case\":{\"available\":true,\"charging\":false,\"level\":80},\"connected\":true,\"conversational_awareness\":true,\"device_name\":\"Kyan's AirPods Pro\",\"ear_detection_behavior\":0,\"is_pro_series\":true,\"left\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":85},\"lid_state\":1,\"model_int\":1,\"model_name\":\"AirPods Pro 3\",\"model_number\":\"A3456\",\"noise_mode\":3,\"one_bud_anc_mode\":true,\"right\":{\"available\":true,\"charging\":false,\"in_ear\":true,\"level\":90},\"schema_version\":2,\"supports_noise_off\":false}"

    function modeKeys(modes) {
        return modes.map(function (m) { return m.key; }).join(",");
    }

    function rowKeys(rows) {
        return rows.map(function (r) { return r.key; }).join(",");
    }

    function test_pro3_full_status() {
        var s = AirpodsModel.parseStatus(fixturePro3);
        compare(s.ok, true);
        compare(s.connected, true);
        compare(s.deviceName, "Kyan's AirPods Pro");
        compare(s.isPro, true);
        compare(s.supportsOff, false);
        compare(s.noiseMode, 3);
        compare(s.left.level, 85);
        compare(s.left.inEar, true);
        compare(s.right.level, 90);
        compare(s.caseBattery.level, 80);
        compare(s.conversationalAwareness, true);
        compare(s.oneBudAnc, true);
        compare(s.lidState, 1);

        var rows = AirpodsModel.batteryRows(s);
        compare(rowKeys(rows), "left,right,case");
        compare(rows[0].hint, "IN EAR");
        compare(rows[2].hint, "");

        var modes = AirpodsModel.modesFor(s);
        compare(modeKeys(modes), "anc,transparency,adaptive");
        verify(modes.every(function (m) { return m.key !== "off"; }));
        var adaptive = modes.filter(function (m) { return m.key === "adaptive"; })[0];
        compare(adaptive.active, true);

        compare(AirpodsModel.stateLine(s), "Adaptive / Lid closed");
    }

    function test_nonpro_status_filters_adaptive_and_keeps_off() {
        var s = AirpodsModel.parseStatus(fixtureNonPro);
        compare(s.ok, true);
        compare(s.isPro, false);
        compare(s.supportsOff, true);

        var modes = AirpodsModel.modesFor(s);
        compare(modeKeys(modes), "off,anc,transparency");
        verify(modes.every(function (m) { return m.key !== "adaptive"; }));

        var rows = AirpodsModel.batteryRows(s);
        compare(rows[1].hint, "IN EAR");
        compare(AirpodsModel.stateLine(s), "Noise cancellation / Lid open");
    }

    function test_absent_pods_return_default_shape_and_no_battery_rows() {
        var s = AirpodsModel.parseStatus(fixtureFreshDaemon);
        compare(s.ok, true);
        compare(s.connected, false);
        compare(s.left.available, false);
        compare(s.left.level, -1);
        compare(s.right.available, false);
        compare(s.caseBattery.available, false);
        compare(AirpodsModel.batteryRows(s).length, 0);
    }

    function test_connected_false_with_battery_still_renders_in_case_state() {
        var s = AirpodsModel.parseStatus(fixtureInCase);
        compare(s.ok, true);
        compare(s.connected, false);

        var rows = AirpodsModel.batteryRows(s);
        compare(rowKeys(rows), "left,right,case");
        compare(rows[0].hint, "CHARGING");
        compare(rows[2].hint, "CHARGING");

        compare(AirpodsModel.stateLine(s), "Not connected / Lid closed");
    }

    function test_wrong_schema_version_returns_default_shape() {
        var s = AirpodsModel.parseStatus(fixtureWrongSchema);
        compare(s.ok, false);
        compare(s.connected, false);
        compare(s.deviceName, "");
        compare(AirpodsModel.batteryRows(s).length, 0);
    }

    function test_malformed_json_returns_default_shape() {
        var s = AirpodsModel.parseStatus("{not json at all");
        compare(s.ok, false);
        compare(s.left.available, false);
        compare(AirpodsModel.batteryRows(s).length, 0);
    }

    function test_empty_text_returns_default_shape() {
        var s = AirpodsModel.parseStatus("");
        compare(s.ok, false);
        compare(s.supportsOff, true);
        compare(s.lidState, 2);
    }

    function test_ear_detection_and_lid_labels() {
        compare(AirpodsModel.earDetectionLabel(0), "PAUSE WHEN ONE IS OUT");
        compare(AirpodsModel.earDetectionLabel(1), "WHEN BOTH ARE OUT");
        compare(AirpodsModel.earDetectionLabel(2), "NEVER");
        compare(AirpodsModel.earDetectionLabel(99), "UNKNOWN");

        compare(AirpodsModel.lidLabel(0), "Lid open");
        compare(AirpodsModel.lidLabel(1), "Lid closed");
        compare(AirpodsModel.lidLabel(2), "");
    }

    function test_noise_mode_label_covers_unknown() {
        compare(AirpodsModel.noiseModeLabel(0), "Off");
        compare(AirpodsModel.noiseModeLabel(1), "Noise cancellation");
        compare(AirpodsModel.noiseModeLabel(2), "Transparency");
        compare(AirpodsModel.noiseModeLabel(3), "Adaptive");
        compare(AirpodsModel.noiseModeLabel(-1), "Unknown");
    }
}
