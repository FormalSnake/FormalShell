import QtQuick
import QtTest
import "../shell/Clock/model.js" as ClockModel

TestCase {
    name: "ClockModel"

    // isoWeek — vectors cross-checked against Python's datetime.isocalendar()

    function test_iso_week_year_start_on_thursday_is_week_one() {
        compare(ClockModel.isoWeek(2026, 0, 1), 1);
    }

    function test_iso_week_ordinary_date() {
        compare(ClockModel.isoWeek(2026, 7, 17), 34);
    }

    function test_iso_week_year_with_53_weeks() {
        compare(ClockModel.isoWeek(2026, 11, 31), 53);
    }

    function test_iso_week_jan_1_belongs_to_prior_year_week_53() {
        compare(ClockModel.isoWeek(2005, 0, 1), 53);
        compare(ClockModel.isoWeek(2005, 0, 2), 53);
    }

    function test_iso_week_dec_31_belongs_to_current_year() {
        compare(ClockModel.isoWeek(2005, 11, 31), 52);
    }

    function test_iso_week_dec_31_belongs_to_next_year_week_one() {
        compare(ClockModel.isoWeek(2007, 11, 31), 1);
    }

    function test_iso_week_jan_1_belongs_to_same_year_week_one() {
        compare(ClockModel.isoWeek(2007, 0, 1), 1);
        compare(ClockModel.isoWeek(2008, 0, 1), 1);
    }

    function test_iso_week_leading_days_before_first_thursday() {
        compare(ClockModel.isoWeek(1977, 0, 1), 53);
        compare(ClockModel.isoWeek(1978, 0, 1), 52);
        compare(ClockModel.isoWeek(1978, 0, 2), 1);
    }

    // pad2

    function test_pad2_single_digit() {
        compare(ClockModel.pad2(5), "05");
    }

    function test_pad2_double_digit() {
        compare(ClockModel.pad2(53), "53");
    }

    // substituteIsoWeek

    function test_substitute_iso_week_replaces_token() {
        var d = new Date(2026, 7, 17);
        compare(ClockModel.substituteIsoWeek("d MMM 'W'ww", d), "d MMM 'W'34");
    }

    function test_substitute_iso_week_replaces_every_occurrence() {
        var d = new Date(2026, 7, 17);
        compare(ClockModel.substituteIsoWeek("ww/ww", d), "34/34");
    }

    function test_substitute_iso_week_leaves_format_untouched_without_token() {
        var d = new Date(2026, 7, 17);
        compare(ClockModel.substituteIsoWeek("hh:mm", d), "hh:mm");
    }

    // stackedLines

    function test_stacked_lines_break_the_time_into_upright_fields() {
        compare(JSON.stringify(ClockModel.stackedLines("09:41")), JSON.stringify(["09", "41"]));
        compare(JSON.stringify(ClockModel.stackedLines("9:41 AM")), JSON.stringify(["9", "41", "AM"]));
        compare(JSON.stringify(ClockModel.stackedLines("Mon 09:41")), JSON.stringify(["Mon", "09", "41"]));
    }

    // The ISO date's dashes are field separators like any other, so the
    // year, month and day each get their own line rather than one line
    // nothing on a 44px strip could hold.
    function test_stacked_lines_break_an_iso_date_on_its_dashes() {
        compare(JSON.stringify(ClockModel.stackedLines("2026-08-17 09:41")),
            JSON.stringify(["2026", "08", "17", "09", "41"]));
    }

    function test_stacked_lines_drop_empty_pieces() {
        compare(JSON.stringify(ClockModel.stackedLines("")), JSON.stringify([]));
        compare(JSON.stringify(ClockModel.stackedLines("  09 : 41  ")), JSON.stringify(["09", "41"]));
    }

    // Every preset in the ring produces at least one line, so no format
    // renders a vertical clock with nothing in it.
    function test_every_preset_stacks_into_at_least_one_line() {
        var ring = ClockModel.formats();
        for (var i = 0; i < ring.length; i++) {
            var rendered = ClockModel.substituteIsoWeek(ring[i], new Date(2026, 7, 17));
            verify(ClockModel.stackedLines(rendered).length > 0);
        }
    }

    // formats / nextFormat

    function test_formats_returns_a_copy() {
        var a = ClockModel.formats();
        a.push("bogus");
        compare(ClockModel.formats().length, ClockModel.CLOCK_FORMATS.length);
    }

    function test_next_format_walks_the_ring_in_order() {
        var ring = ClockModel.formats();
        for (var i = 0; i < ring.length; i++)
            compare(ClockModel.nextFormat(ring[i]), ring[(i + 1) % ring.length]);
    }

    function test_next_format_wraps_from_last_to_first() {
        var ring = ClockModel.formats();
        compare(ClockModel.nextFormat(ring[ring.length - 1]), ring[0]);
    }

    function test_next_format_unknown_current_starts_at_top() {
        compare(ClockModel.nextFormat("nonsense"), ClockModel.CLOCK_FORMATS[0]);
    }

    // usesMeridiem

    function test_uses_meridiem_reads_the_twelve_hour_presets() {
        compare(ClockModel.usesMeridiem("h:mm AP"), true);
        compare(ClockModel.usesMeridiem("h:mm ap"), true);
    }

    function test_uses_meridiem_is_false_for_every_other_preset() {
        var ring = ClockModel.formats();
        for (var i = 0; i < ring.length; i++) {
            if (ring[i].indexOf("AP") >= 0 || ring[i].indexOf("ap") >= 0)
                continue;
            compare(ClockModel.usesMeridiem(ring[i]), false, ring[i]);
        }
    }
}
