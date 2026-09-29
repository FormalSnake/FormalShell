import QtQuick
import QtTest
import "../shell/Menu/actions.js" as Actions
import "../shell/Menu/hints.js" as Hints
import "../shell/Menu/providers.js" as Providers

TestCase {
    name: "MenuDevices"

    function test_id_part_round_trips_and_has_no_dot() {
        var keys = ["a.b", "a:b", "a b", "ü", "plain"];
        for (var i = 0; i < keys.length; i++) {
            var part = Providers.idPart(keys[i]);
            compare(part.indexOf("."), -1);
            compare(decodeURIComponent(part), keys[i]);
        }
    }

    function _labels(ctx) {
        return Actions.hints(ctx).map(function (h) { return h.label; });
    }

    function test_alternate_hint_shows_its_label() {
        verify(_labels({ mode: "menu", alternateLabel: "Forget" }).indexOf("Forget") >= 0);
    }

    function test_alternate_hint_absent_without_a_label() {
        compare(_labels({ mode: "menu", alternateLabel: "" }).indexOf("Forget"), -1);
        compare(Actions.hints({ mode: "menu", atRoot: true }).length, 1);
    }

    function test_alternate_hint_absent_while_confirming() {
        compare(_labels({ mode: "menu", alternateLabel: "Forget", confirming: true }).indexOf("Forget"), -1);
    }

    function test_alternate_hint_absent_in_input_mode() {
        compare(_labels({ mode: "input", alternateLabel: "Forget" }), ["Cancel"]);
    }

    function _net(name, extra) {
        return Object.assign({ name: name, known: false, connected: false, secured: true, enterprise: false, signal: 0.5 }, extra || {});
    }

    function _wifi(networks, extra) {
        return Providers.wifiRows(Object.assign({ hasDevice: true, enabled: true, networks: networks,
            actionSsid: "", actionKind: "", failureSsid: "", failureText: "" }, extra || {}));
    }

    function _descOf(rows, name) {
        return rows.filter(function (r) { return r.label === name; })[0].desc;
    }

    function test_wifi_no_device_is_one_note() {
        var rows = Providers.wifiRows({ hasDevice: false, enabled: false, networks: [] });
        compare(rows.length, 1);
        compare(rows[0].id, "wifi.unavailable");
        compare(rows[0].kind, "note");
    }

    function test_wifi_off_offers_to_turn_on() {
        var rows = Providers.wifiRows({ hasDevice: true, enabled: false, networks: [] });
        compare(rows[0].id, "wifi.off");
        compare(rows[0].action, "@ipc:wifi.enable");
    }

    function test_wifi_no_networks_is_one_note() {
        var rows = _wifi([]);
        compare(rows[0].id, "wifi.empty");
        compare(rows[0].kind, "note");
    }

    function test_wifi_order_connected_saved_nearby() {
        var rows = _wifi([
            _net("Near", { signal: 0.9 }),
            _net("Saved", { known: true, signal: 0.2 }),
            _net("Live", { known: true, connected: true, signal: 0.1 })
        ]);
        compare(rows.map(function (r) { return r.label; }), ["Live", "Saved", "Near"]);
        compare(rows.map(function (r) { return r.section; }), ["Saved", "Saved", "Nearby"]);
    }

    function test_wifi_local_only_on_nearby_rows_only() {
        var rows = _wifi([_net("Near"), _net("Saved", { known: true })]);
        compare(rows.filter(function (r) { return r.localOnly; }).map(function (r) { return r.label; }), ["Near"]);
    }

    function test_wifi_dotted_ssid_has_one_level() {
        var rows = _wifi([_net("a.b", { known: true })]);
        compare(rows.length, 1);
        compare(rows[0].id, "wifi.net.a%2Eb");
        compare(rows[0].id.split(".").length, 3);
    }

    function test_wifi_tick_condition_names_the_ssid() {
        compare(_wifi([_net("Home", { known: true })])[0].checked, "@state:wifi.ssid=Home");
    }

    function test_wifi_forget_only_on_saved_rows() {
        var rows = _wifi([_net("Near"), _net("Saved", { known: true })]);
        var byName = {};
        rows.forEach(function (r) { byName[r.label] = r; });
        compare(byName.Saved.alternate, "@ipc:wifi.forget:Saved");
        compare(byName.Saved.alternateLabel, "Forget");
        compare(byName.Near.alternate, undefined);
    }

    function test_wifi_desc_for_unknown_networks() {
        var rows = _wifi([_net("Sec"), _net("Corp", { enterprise: true }), _net("Open", { secured: false })]);
        compare(_descOf(rows, "Sec"), "Secured");
        compare(_descOf(rows, "Corp"), "Enterprise");
        compare(_descOf(rows, "Open"), "");
    }

    function test_wifi_desc_for_the_action_in_flight() {
        var rows = _wifi([_net("A", { known: true }), _net("B", { known: true })], { actionSsid: "A", actionKind: "forget" });
        compare(_descOf(rows, "A"), "Forgetting");
        compare(_descOf(rows, "B"), "");
    }

    function test_wifi_failure_text_stays_on_its_own_row() {
        var rows = _wifi([_net("A", { known: true }), _net("B", { known: true })], { failureSsid: "A", failureText: "Wrong password" });
        compare(_descOf(rows, "A"), "Wrong password");
        compare(_descOf(rows, "B"), "");
    }

    function test_wifi_hidden_ssid_is_skipped() {
        var rows = _wifi([_net(""), _net("Real")]);
        compare(rows.length, 1);
        compare(rows[0].label, "Real");
    }

    function _bt(devices, extra) {
        return Providers.bluetoothRows(Object.assign({ available: true, enabled: true, devices: devices }, extra || {}));
    }

    function _dev(address, name, extra) {
        return Object.assign({ address: address, name: name, connected: false, paired: true, bonded: false,
            trusted: false, activity: "", battery: "" }, extra || {});
    }

    function test_bluetooth_no_adapter_is_one_note() {
        var rows = Providers.bluetoothRows({ available: false, enabled: false, devices: [] });
        compare(rows.length, 1);
        compare(rows[0].id, "bluetooth.unavailable");
        compare(rows[0].kind, "note");
    }

    function test_bluetooth_off_offers_to_turn_on() {
        var rows = Providers.bluetoothRows({ available: true, enabled: false, devices: [] });
        compare(rows[0].id, "bluetooth.off");
        compare(rows[0].action, "@ipc:bluetooth.power:on");
    }

    function test_bluetooth_no_paired_devices_is_one_note() {
        var rows = _bt([_dev("AA:01", "Seen", { paired: false })]);
        compare(rows.length, 1);
        compare(rows[0].id, "bluetooth.empty");
        compare(rows[0].kind, "note");
    }

    function test_bluetooth_order_connected_then_paired() {
        var rows = _bt([_dev("AA:01", "Alpha"), _dev("AA:02", "Zed", { connected: true }), _dev("AA:03", "Beta")]);
        compare(rows.map(function (r) { return r.label; }), ["Zed", "Alpha", "Beta"]);
    }

    function test_bluetooth_unnamed_devices_are_dropped() {
        var rows = _bt([_dev("AA:01", ""), _dev("AA:02", "AA:BB:CC:DD:EE:FF"), _dev("AA:03", "Real")]);
        compare(rows.length, 1);
        compare(rows[0].label, "Real");
    }

    function test_bluetooth_desc_prefers_activity_then_battery() {
        var rows = _bt([
            _dev("AA:01", "A", { connected: true, activity: "Connecting…", battery: "80%" }),
            _dev("AA:02", "B", { connected: true, battery: "50%" }),
            _dev("AA:03", "C", { connected: true })
        ]);
        compare(_descOf(rows, "A"), "Connecting…");
        compare(_descOf(rows, "B"), "50%");
        compare(_descOf(rows, "C"), "");
    }

    function test_bluetooth_row_ids_action_and_tick() {
        var rows = _bt([_dev("aa:bb", "Buds")]);
        compare(rows[0].id, "bluetooth.dev.aa%3Abb");
        compare(rows[0].action, "@ipc:bluetooth.toggle:aa:bb");
        compare(rows[0].checked, "@state:bluetooth.connected=AA:BB");
        compare(rows[0].keepOpen, true);
    }

    // A device row names what Enter does to it, and carries no "Command"
    // badge beside its label.
    function test_device_rows_carry_their_own_verb() {
        var wifi = _wifi([_net("Home", { known: true, connected: true }), _net("Cafe")]);
        compare(Actions.primaryAction({ node: wifi[0] }).label, "Disconnect");
        compare(Actions.primaryAction({ node: wifi[1] }).label, "Connect");
        var bt = _bt([_dev("aa:bb", "Buds", { connected: true }), _dev("cc:dd", "Pad")]);
        compare(bt[0].verb, "Disconnect");
        compare(bt[1].verb, "Connect");
        var audio = Providers.audioRows([{ name: "sink", label: "Speakers", isSink: true }]);
        compare(audio[0].verb, "Use");
        var radio = Providers.radioRows({ running: true, favorites: [{ uuid: "u1", name: "Jazz" }] });
        compare(radio[0].verb, "Stop");
        compare(radio[1].verb, "Play");
        compare(Providers.radioResultRows([{ uuid: "u2", name: "Rock" }], {})[0].verb, "Play");
        [wifi[0], bt[0], audio[0], radio[1]].forEach(function (row) {
            compare(Hints.accessoryFor(row), "");
        });
    }

    function test_audio_no_devices_is_one_note() {
        var rows = Providers.audioRows([]);
        compare(rows.length, 1);
        compare(rows[0].id, "audio.unavailable");
        compare(rows[0].kind, "note");
    }

    function test_audio_sections_actions_and_ticks() {
        var rows = Providers.audioRows([
            { name: "alsa_output.pci-0000_00_1f.3.analog-stereo", label: "Speakers", isSink: true },
            { name: "alsa_input.usb", label: "Mic", isSink: false }
        ]);
        compare(rows.length, 2);
        compare(rows[0].id, "audio.output.alsa_output%2Epci-0000_00_1f%2E3%2Eanalog-stereo");
        compare(rows[0].section, "Output");
        compare(rows[0].action, "@ipc:audio.sink:alsa_output.pci-0000_00_1f.3.analog-stereo");
        compare(rows[0].checked, "@state:audio.sink=alsa_output.pci-0000_00_1f.3.analog-stereo");
        compare(rows[1].id, "audio.input.alsa_input%2Eusb");
        compare(rows[1].section, "Input");
        compare(rows[1].action, "@ipc:audio.source:alsa_input.usb");
        compare(rows[1].checked, "@state:audio.source=alsa_input.usb");
        compare(rows[0].keepOpen, true);
        compare(rows[1].keepOpen, true);
    }

    function test_audio_outputs_only_has_no_input_note() {
        var rows = Providers.audioRows([{ name: "o", label: "O", isSink: true }]);
        compare(rows.length, 1);
        compare(rows[0].kind, "action");
    }

    function test_radio_trigger_parsing() {
        compare(Providers.radioTriggerQuery(":r"), "");
        compare(Providers.radioTriggerQuery(":r jazz"), "jazz");
        compare(Providers.radioTriggerQuery(":radio"), null);
        compare(Providers.radioTriggerQuery(":rx"), null);
        compare(Providers.radioTriggerQuery("jazz"), null);
    }

    function test_radio_favorites_ticks_and_alternates() {
        var rows = Providers.radioRows({ running: false, favorites: [{ uuid: "u-1", name: "Groove", country: "France" }] });
        compare(rows.length, 1);
        compare(rows[0].id, "radio.fav.u-1");
        compare(rows[0].label, "Groove");
        compare(rows[0].desc, "France");
        compare(rows[0].action, "@ipc:radio.fav:u-1");
        compare(rows[0].checked, "@state:radio.station=u-1");
        compare(rows[0].keepOpen, true);
        compare(rows[0].alternate, "@ipc:radio.unfavorite:u-1");
        compare(rows[0].alternateLabel, "Remove favorite");
        verify(rows[0].localOnly !== true);
    }

    function test_radio_stop_only_while_running() {
        compare(Providers.radioRows({ running: false, favorites: [] }).length, 0);
        var rows = Providers.radioRows({ running: true, favorites: [] });
        compare(rows.length, 1);
        compare(rows[0].id, "radio.stop");
        compare(rows[0].action, "@ipc:radio.stop");
    }

    function test_radio_results_are_local_only_with_alternate_per_favorite_set() {
        var rows = Providers.radioResultRows([
            { uuid: "a", name: "A", country: "Spain", codec: "MP3" },
            { uuid: "b", name: "B", country: "", codec: "AAC" }
        ], { a: true });
        compare(rows[0].localOnly, true);
        compare(rows[0].desc, "Spain MP3");
        compare(rows[0].action, "@ipc:radio.play:a");
        compare(rows[0].alternate, "@ipc:radio.unfavorite:a");
        compare(rows[0].alternateLabel, "Remove favorite");
        compare(rows[1].desc, "AAC");
        compare(rows[1].alternate, "@ipc:radio.favorite:b");
        compare(rows[1].alternateLabel, "Add favorite");
        verify(rows[1].keepOpen !== true);
    }
}
