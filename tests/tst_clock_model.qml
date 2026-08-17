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
}
