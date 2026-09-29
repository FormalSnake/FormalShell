import QtQuick
import QtTest
import "../shell/Monitor/format.js" as Format
import "../shell/Monitor/history.js" as History

TestCase {
    name: "MonitorFormat"

    function test_missing_readings_are_dashes_never_zeros() {
        compare(Format.pct(null), "--");
        compare(Format.pct(undefined), "--");
        compare(Format.pct(NaN), "--");
        compare(Format.procPct(null), "--");
        compare(Format.bytes(null), "--");
        compare(Format.rate(undefined), "--");
    }

    function test_percentages() {
        compare(Format.pct(0.514), "51%");
        compare(Format.pct(0), "0%");
        compare(Format.procPct(0.0041), "0.4%");
        compare(Format.procPct(0.165), "16.5%");
    }

    function test_bytes_step_through_binary_units() {
        compare(Format.bytes(0), "0B");
        compare(Format.bytes(141), "141B");
        compare(Format.bytes(1536), "1.5K");
        compare(Format.bytes(3.6 * 1024 * 1024), "3.6M");
        compare(Format.rate(2048), "2.0K/s");
    }

    function test_push_skips_unmeasured_samples() {
        compare(History.push([], null), []);
        compare(History.push([0.1], NaN), [0.1]);
        compare(History.push([0.1], 0.2), [0.1, 0.2]);
    }

    function test_push_keeps_the_newest_capacity_samples() {
        var s = [];
        for (var i = 0; i < 5; i++)
            s = History.push(s, i, 3);
        compare(s, [2, 3, 4]);
    }

    function test_push_does_not_mutate_its_input() {
        var before = [0.1];
        History.push(before, 0.2);
        compare(before, [0.1]);
    }

    function test_ceiling_has_a_floor() {
        compare(History.ceiling([], 1024), 1024);
        compare(History.ceiling([10, 20], 1024), 1024);
        compare(History.ceiling([10, 5000], 1024), 5000);
    }

    function test_points_spread_across_the_box_until_the_series_is_full() {
        var pts = History.points([0.5], 100, 20, 1, 11);
        compare(pts.length, 1);
        compare(pts[0].x, 100);
        compare(pts[0].y, 10);
        pts = History.points([0, 1], 100, 20, 1, 11);
        compare(pts[0].x, 0);
        compare(pts[0].y, 20);
        compare(pts[1].x, 100);
        compare(pts[1].y, 0);
        pts = History.points([0, 0.5, 1], 100, 20, 1, 11);
        compare(pts[1].x, 50);
    }

    function test_points_clamp_to_the_box_and_refuse_a_zero_scale() {
        compare(History.points([2], 100, 20, 1, 11)[0].y, 0);
        compare(History.points([1], 100, 20, 0, 11), []);
    }
}
