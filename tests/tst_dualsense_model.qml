import QtQuick
import QtTest
import "../shell/Dualsense/model.js" as DualsenseModel

TestCase {
    name: "DualsenseModel"

    // parseSupply: real-shaped sysfs text, trailing newline included since
    // `cat` on a sysfs attribute always ends one.

    function test_parse_supply_ok_reading() {
        var s = DualsenseModel.parseSupply("80\n", "Discharging\n");
        compare(s.percent, 80);
        compare(s.statusLabel, "Discharging");
        compare(s.warn, false);
        compare(s.critical, false);
    }

    function test_parse_supply_warn_band() {
        var s = DualsenseModel.parseSupply("20\n", "Discharging\n");
        compare(s.warn, true);
        compare(s.critical, false);
    }

    function test_parse_supply_critical_band_wins_over_warn() {
        var s = DualsenseModel.parseSupply("10\n", "Discharging\n");
        compare(s.critical, true);
        compare(s.warn, false);
    }

    function test_parse_supply_charging_status() {
        var s = DualsenseModel.parseSupply("95\n", "Charging\n");
        compare(s.percent, 95);
        compare(s.statusLabel, "Charging");
    }

    function test_parse_supply_missing_files() {
        var s = DualsenseModel.parseSupply("", "");
        compare(s.percent, -1);
        compare(s.statusLabel, "");
        compare(s.warn, false);
        compare(s.critical, false);
    }

    function test_parse_supply_malformed_capacity() {
        var s = DualsenseModel.parseSupply("not a number\n", "Discharging\n");
        compare(s.percent, -1);
        compare(s.critical, false);
        compare(s.warn, false);
    }

    // parseLightbar: "R G B" -> "#rrggbb".

    function test_parse_lightbar_ok() {
        compare(DualsenseModel.parseLightbar("255 0 64\n"), "#ff0040");
    }

    function test_parse_lightbar_low_values_pad_to_two_digits() {
        compare(DualsenseModel.parseLightbar("0 8 15\n"), "#00080f");
    }

    function test_parse_lightbar_missing_file() {
        compare(DualsenseModel.parseLightbar(""), null);
    }

    function test_parse_lightbar_malformed() {
        compare(DualsenseModel.parseLightbar("255 0\n"), null);
        compare(DualsenseModel.parseLightbar("red green blue\n"), null);
        compare(DualsenseModel.parseLightbar("255 0 300\n"), null);
    }

    // parsePlayerLeds: lit count over exactly 5 entries.

    function test_parse_player_leds_one_lit() {
        compare(DualsenseModel.parsePlayerLeds(["0", "1", "0", "0", "0"]), 1);
    }

    function test_parse_player_leds_none_lit() {
        compare(DualsenseModel.parsePlayerLeds(["0", "0", "0", "0", "0"]), 0);
    }

    function test_parse_player_leds_missing_entries_read_as_unlit() {
        compare(DualsenseModel.parsePlayerLeds([null, "1", null, null, null]), 1);
    }

    function test_parse_player_leds_not_an_array() {
        compare(DualsenseModel.parsePlayerLeds(null), 0);
    }

    // stateLine.

    function test_state_line_discharging() {
        var s = DualsenseModel.parseSupply("80\n", "Discharging\n");
        compare(DualsenseModel.stateLine(s), "DISCHARGING");
    }

    function test_state_line_full() {
        var s = DualsenseModel.parseSupply("100\n", "Full\n");
        compare(DualsenseModel.stateLine(s), "FULL");
    }

    function test_state_line_no_controller() {
        var s = DualsenseModel.parseSupply("", "");
        compare(DualsenseModel.stateLine(s), "");
    }
}
