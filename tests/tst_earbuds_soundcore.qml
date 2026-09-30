import QtQuick
import QtTest
import "../shell/Earbuds/soundcore.js" as Soundcore
import "../shell/Earbuds/model.js" as Model

TestCase {
    name: "EarbudsSoundcore"

    // Fixtures are stdout captured from a real openscq30 2.12.0 binary (nix
    // build of github.com/Oppzippy/OpenSCQ30 v2.12.0, run on the aarch64
    // test VM against demo devices, `paired-devices add --demo`), so the
    // shapes are the CLI's own. The list-settings ones are trimmed to the
    // settings this adapter reads; battery levels are the demo's 0/5. The
    // paired-list shape is the same one printed in cli/src/cli.rs's
    // `paired-devices list` help text. Demo devices: 00:00:00:00:00:01
    // SoundcoreA3027 (Life Q35, one battery), 00:00:00:00:00:03
    // SoundcoreA3947 (Liberty 4 NC, earbuds with a case).

    property string paired: "[{\"macAddress\":\"00:00:00:00:00:01\",\"model\":\"SoundcoreA3027\",\"isDemo\":true},{\"macAddress\":\"AC:12:2F:11:22:33\",\"model\":\"SoundcoreA3947\",\"isDemo\":false},{\"macAddress\":\"AC:12:2F:44:55:66\",\"model\":\"SoundcoreA3027\",\"isDemo\":false}]"

    property string settingsHeadphone: "{\"ambientSoundMode\":{\"type\":\"select\",\"setting\":{\"options\":[\"Normal\",\"Transparency\",\"NoiseCanceling\"],\"localizedOptions\":[\"Normal\",\"Transparency\",\"Noise Canceling\"]}},\"noiseCancelingMode\":{\"type\":\"select\",\"setting\":{\"options\":[\"Transport\",\"Indoor\",\"Outdoor\"],\"localizedOptions\":[\"Transport\",\"Indoor\",\"Outdoor\"]}},\"presetEqualizerProfile\":{\"type\":\"optionalSelect\",\"setting\":{\"options\":[\"SoundcoreSignature\",\"Acoustic\",\"BassBooster\",\"BassReducer\",\"Classical\",\"Podcast\",\"Dance\",\"Deep\",\"Electronic\",\"Flat\",\"HipHop\",\"Jazz\",\"Latin\",\"Lounge\",\"Piano\",\"Pop\",\"RnB\",\"Rock\",\"SmallSpeakers\",\"SpokenWord\",\"TrebleBooster\",\"TrebleReducer\"],\"localizedOptions\":[\"Soundcore Signature\",\"Acoustic\",\"Bass Booster\",\"Bass Reducer\",\"Classical\",\"Podcast\",\"Dance\",\"Deep\",\"Electronic\",\"Flat\",\"Hip Hop\",\"Jazz\",\"Latin\",\"Lounge\",\"Piano\",\"Pop\",\"RnB\",\"Rock\",\"Small Speakers\",\"Spoken Word\",\"Treble Booster\",\"Treble Reducer\"]}},\"isCharging\":{\"type\":\"information\"},\"batteryLevel\":{\"type\":\"information\"},\"wearingDetection\":{\"type\":\"toggle\"}}"

    property string settingsEarbuds: "{\"ambientSoundMode\":{\"type\":\"select\",\"setting\":{\"options\":[\"NoiseCanceling\",\"Transparency\",\"Normal\"],\"localizedOptions\":[\"Noise Canceling\",\"Transparency\",\"Normal\"]}},\"transparencyMode\":{\"type\":\"select\",\"setting\":{\"options\":[\"FullyTransparent\",\"VocalMode\"],\"localizedOptions\":[\"Fully Transparent\",\"Vocal Mode\"]}},\"presetEqualizerProfile\":{\"type\":\"optionalSelect\",\"setting\":{\"options\":[\"SoundcoreSignature\",\"Acoustic\",\"BassBooster\",\"BassReducer\",\"Classical\",\"Podcast\",\"Dance\",\"Deep\",\"Electronic\",\"Flat\",\"HipHop\",\"Jazz\",\"Latin\",\"Lounge\",\"Piano\",\"Pop\",\"RnB\",\"Rock\",\"SmallSpeakers\",\"SpokenWord\",\"TrebleBooster\",\"TrebleReducer\"],\"localizedOptions\":[\"Soundcore Signature\",\"Acoustic\",\"Bass Booster\",\"Bass Reducer\",\"Classical\",\"Podcast\",\"Dance\",\"Deep\",\"Electronic\",\"Flat\",\"Hip Hop\",\"Jazz\",\"Latin\",\"Lounge\",\"Piano\",\"Pop\",\"RnB\",\"Rock\",\"Small Speakers\",\"Spoken Word\",\"Treble Booster\",\"Treble Reducer\"]}},\"isChargingLeft\":{\"type\":\"information\"},\"isChargingRight\":{\"type\":\"information\"},\"batteryLevelLeft\":{\"type\":\"information\"},\"batteryLevelRight\":{\"type\":\"information\"},\"caseBatteryLevel\":{\"type\":\"information\"}}"

    property string valuesHeadphone: "[{\"settingId\":\"ambientSoundMode\",\"value\":{\"type\":\"string\",\"value\":\"NoiseCanceling\"}},{\"settingId\":\"presetEqualizerProfile\",\"value\":{\"type\":\"optionalString\",\"value\":\"SoundcoreSignature\"}},{\"settingId\":\"batteryLevel\",\"value\":{\"type\":\"string\",\"value\":\"0/5\"}},{\"settingId\":\"isCharging\",\"value\":{\"type\":\"string\",\"value\":\"No\"}}]"

    property string valuesEarbuds: "[{\"settingId\":\"ambientSoundMode\",\"value\":{\"type\":\"string\",\"value\":\"NoiseCanceling\"}},{\"settingId\":\"presetEqualizerProfile\",\"value\":{\"type\":\"optionalString\",\"value\":\"SoundcoreSignature\"}},{\"settingId\":\"batteryLevelLeft\",\"value\":{\"type\":\"string\",\"value\":\"0/5\"}},{\"settingId\":\"batteryLevelRight\",\"value\":{\"type\":\"string\",\"value\":\"0/5\"}},{\"settingId\":\"caseBatteryLevel\",\"value\":{\"type\":\"string\",\"value\":\"0/5\"}},{\"settingId\":\"isChargingLeft\",\"value\":{\"type\":\"string\",\"value\":\"No\"}},{\"settingId\":\"isChargingRight\",\"value\":{\"type\":\"string\",\"value\":\"No\"}}]"

    // The same shape with values a real pair would report, edited by hand:
    // 4/5 and 3/5 steps, the right bud charging, a preset outside the row.
    property string valuesEdited: "[{\"settingId\":\"ambientSoundMode\",\"value\":{\"type\":\"string\",\"value\":\"Transparency\"}},{\"settingId\":\"presetEqualizerProfile\",\"value\":{\"type\":\"optionalString\",\"value\":\"Jazz\"}},{\"settingId\":\"batteryLevelLeft\",\"value\":{\"type\":\"string\",\"value\":\"4/5\"}},{\"settingId\":\"batteryLevelRight\",\"value\":{\"type\":\"string\",\"value\":\"3/5\"}},{\"settingId\":\"caseBatteryLevel\",\"value\":{\"type\":\"string\",\"value\":\"5/5\"}},{\"settingId\":\"isChargingLeft\",\"value\":{\"type\":\"string\",\"value\":\"No\"}},{\"settingId\":\"isChargingRight\",\"value\":{\"type\":\"string\",\"value\":\"Yes\"}}]"

    function keys(list, field) {
        return list.map(function (x) { return x[field]; }).join(",");
    }

    function bt(address, name, connected) {
        return { address: address, name: name, deviceName: name, connected: connected };
    }

    function info(address, model, name) {
        return { address: address, model: model, name: name };
    }

    function test_paired_list_parses_and_skips_junk() {
        var p = Soundcore.parsePaired(paired);
        compare(p.length, 3);
        compare(p[0].demo, true);
        compare(p[1].address, "AC:12:2F:11:22:33");
        compare(p[1].model, "SoundcoreA3947");
        compare(Soundcore.parsePaired("").length, 0);
        compare(Soundcore.parsePaired("Error: no session").length, 0);
        compare(Soundcore.parsePaired("{\"macAddress\":\"AC:12:2F:11:22:33\"}").length, 0);
        compare(Soundcore.parsePaired("[{\"macAddress\":\"; rm -rf\",\"model\":\"x\"}]").length, 0);
    }

    function test_only_connected_non_demo_paired_devices_are_listed() {
        var p = Soundcore.parsePaired(paired);
        var found = Soundcore.connectedPaired(p, [
            bt("ac:12:2f:11:22:33", "Liberty 4 NC", true),
            bt("AC:12:2F:44:55:66", "Life Q35", false),
            bt("00:00:00:00:00:01", "Demo", true),
            bt("11:22:33:44:55:66", "Unknown speaker", true)
        ]);
        compare(found.length, 1);
        compare(found[0].address, "AC:12:2F:11:22:33");
        compare(found[0].model, "SoundcoreA3947");
        compare(found[0].name, "Liberty 4 NC");
        compare(Soundcore.connectedPaired(p, []).length, 0);
    }

    function test_capabilities_headphone() {
        var caps = Soundcore.parseCapabilities(settingsHeadphone);
        compare(keys(caps.modes, "value"), "Normal,NoiseCanceling,Transparency");
        compare(keys(caps.presets, "value"), "SoundcoreSignature,BassBooster,TrebleBooster,Podcast");
        compare(caps.ids.join(","), "ambientSoundMode,presetEqualizerProfile,batteryLevel,isCharging");
        compare(caps.single, true);
        compare(caps.dual, false);
        compare(Soundcore.getArgs(caps).join(" "), "--get ambientSoundMode --get presetEqualizerProfile --get batteryLevel --get isCharging");
    }

    function test_capabilities_earbuds() {
        var caps = Soundcore.parseCapabilities(settingsEarbuds);
        compare(caps.dual, true);
        compare(caps.single, false);
        compare(caps.hasCase, true);
        compare(caps.ids.join(","), "ambientSoundMode,presetEqualizerProfile,batteryLevelLeft,isChargingLeft,batteryLevelRight,isChargingRight,caseBatteryLevel");
    }

    function test_capabilities_reject_non_objects() {
        compare(Soundcore.parseCapabilities(""), null);
        compare(Soundcore.parseCapabilities("[]"), null);
        var bare = Soundcore.parseCapabilities("{}");
        compare(bare.ids.length, 0);
    }

    function test_values_parse() {
        var v = Soundcore.parseValues(valuesEarbuds);
        compare(v.ambientSoundMode, "NoiseCanceling");
        compare(v.batteryLevelLeft, "0/5");
        compare(v.isChargingRight, "No");
        compare(Object.keys(Soundcore.parseValues("[]")).length, 0);
        compare(Object.keys(Soundcore.parseValues("Error: nope")).length, 0);
    }

    function test_headphone_device() {
        var caps = Soundcore.parseCapabilities(settingsHeadphone);
        var d = Soundcore.normalise(info("AC:12:2F:44:55:66", "SoundcoreA3027", "Life Q35"), caps, Soundcore.parseValues(valuesHeadphone));
        compare(d.key, "soundcore:AC:12:2F:44:55:66");
        compare(d.backend, "soundcore");
        compare(d.kind, "headphone");
        compare(d.name, "Life Q35");
        compare(d.connected, true);
        compare(d.stateLine, "Noise cancellation");
        var rows = Model.batteryRows(d);
        compare(keys(rows, "key"), "single");
        compare(rows[0].level, 0);
        compare(keys(d.controls, "key"), "mode,eq");
        compare(keys(Model.sections(d), "section"), "Listening mode,Equalizer");
        var mode = Model.control(d, "mode");
        compare(mode.kind, "choice");
        compare(keys(mode.options, "value"), "Normal,NoiseCanceling,Transparency");
        compare(keys(mode.options, "icon"), "circle-off,ear-off,ear");
        compare(mode.value, "NoiseCanceling");
        compare(Model.control(d, "eq").value, "SoundcoreSignature");
    }

    function test_earbuds_device_with_levels() {
        var caps = Soundcore.parseCapabilities(settingsEarbuds);
        var d = Soundcore.normalise(info("AC:12:2F:11:22:33", "SoundcoreA3947", "Liberty 4 NC"), caps, Soundcore.parseValues(valuesEdited));
        compare(d.kind, "earbuds");
        compare(d.stateLine, "Transparency");
        var rows = Model.batteryRows(d);
        compare(keys(rows, "key"), "left,right,case");
        compare(rows[0].level, 80);
        compare(rows[1].level, 60);
        compare(rows[1].hint, "Charging");
        compare(rows[2].level, 100);
        compare(Model.worstLevel(d), 60);
        compare(Model.control(d, "mode").value, "Transparency");
        // Jazz is a real preset the row has no button for: nothing lit.
        compare(Model.control(d, "eq").value, null);
    }

    function test_failed_read_lists_device_without_controls() {
        var caps = Soundcore.parseCapabilities(settingsEarbuds);
        var d = Soundcore.normalise(info("AC:12:2F:11:22:33", "SoundcoreA3947", ""), caps, {});
        compare(d.name, "Soundcore");
        compare(d.controls.length, 0);
        compare(d.batteries.length, 0);
        compare(d.stateLine, "");
    }

    function test_unknown_battery_text_is_dropped() {
        var caps = Soundcore.parseCapabilities(settingsHeadphone);
        var d = Soundcore.normalise(info("AC:12:2F:44:55:66", "SoundcoreA3027", "Q"), caps, { batteryLevel: "n/a", isCharging: "No" });
        compare(d.batteries.length, 0);
        d = Soundcore.normalise(info("AC:12:2F:44:55:66", "SoundcoreA3027", "Q"), caps, { batteryLevel: "1/0" });
        compare(d.batteries.length, 0);
    }

    function test_command_allow_list() {
        var caps = Soundcore.parseCapabilities(settingsEarbuds);
        compare(Soundcore.command("mode", "NoiseCanceling", caps).join(" "), "--set ambientSoundMode=NoiseCanceling");
        compare(Soundcore.command("eq", "BassBooster", caps).join(" "), "--set presetEqualizerProfile=BassBooster");
        compare(Soundcore.command("mode", "AirplaneMode", caps).length, 0);
        compare(Soundcore.command("mode", "Normal; reboot", caps).length, 0);
        compare(Soundcore.command("eq", "Jazz", caps).length, 0);
        compare(Soundcore.command("battery", "x", caps).length, 0);
        compare(Soundcore.command("mode", "Normal", null).length, 0);
        // A model whose select lacks a mode refuses it.
        var caps2 = Soundcore.parseCapabilities("{\"ambientSoundMode\":{\"type\":\"select\",\"setting\":{\"options\":[\"Normal\",\"NoiseCanceling\"]}}}");
        compare(Soundcore.command("mode", "Transparency", caps2).length, 0);
        compare(Soundcore.command("mode", "Normal", caps2).length, 2);
    }

    function test_argv_builders_refuse_a_bad_address() {
        compare(Soundcore.pairedArgv().join(" "), "openscq30 paired-devices list --json");
        compare(Soundcore.settingsArgv("AC:12:2F:11:22:33").join(" "), "openscq30 device -a AC:12:2F:11:22:33 list-settings --no-categories --json");
        compare(Soundcore.settingArgv("AC:12:2F:11:22:33", ["--set", "ambientSoundMode=Normal"]).join(" "), "openscq30 device -a AC:12:2F:11:22:33 setting --set ambientSoundMode=Normal --json");
        compare(Soundcore.settingArgv("--help", ["--get", "x"]).length, 0);
        compare(Soundcore.settingsArgv("").length, 0);
    }
}
