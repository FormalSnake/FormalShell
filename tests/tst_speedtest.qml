import QtQuick
import QtTest
import "../shell/Network/speedtest.js" as SpeedTest

TestCase {
    name: "SpeedTest"

    // mbps

    function test_mbps_normal_rate() {
        // 1,000,000 bytes over 1000ms = 8 Mbps.
        compare(SpeedTest.mbps(1000000, 1000), 8);
    }

    function test_mbps_zero_duration_guard() {
        compare(SpeedTest.mbps(1000000, 0), 0);
    }

    function test_mbps_negative_duration_guard() {
        compare(SpeedTest.mbps(1000000, -50), 0);
    }

    function test_mbps_counter_reset_guard() {
        // bytes went backwards (interface flapped / counter wrapped).
        compare(SpeedTest.mbps(-500, 1000), 0);
    }

    function test_mbps_zero_delta() {
        compare(SpeedTest.mbps(0, 1000), 0);
    }

    // formatMbps

    function test_formatMbps_zero() {
        compare(SpeedTest.formatMbps(0), "0.0");
    }

    function test_formatMbps_negative_reads_as_zero() {
        compare(SpeedTest.formatMbps(-3), "0.0");
    }

    function test_formatMbps_under_ten_keeps_decimal() {
        compare(SpeedTest.formatMbps(7.34), "7.3");
    }

    function test_formatMbps_ten_and_above_rounds() {
        compare(SpeedTest.formatMbps(10), "10");
        compare(SpeedTest.formatMbps(123.6), "124");
    }

    // fillFraction

    function test_fillFraction_zero() {
        compare(SpeedTest.fillFraction(0, 1000), 0);
    }

    function test_fillFraction_mid_scale() {
        compare(SpeedTest.fillFraction(500, 1000), 0.5);
    }

    function test_fillFraction_caps_at_one() {
        compare(SpeedTest.fillFraction(5000, 1000), 1);
    }

    function test_fillFraction_default_max_when_omitted() {
        compare(SpeedTest.fillFraction(500, undefined), 0.5);
    }

    // initWindow / addSample

    function test_first_sample_seeds_zero_rates() {
        var w = SpeedTest.addSample(SpeedTest.initWindow(), 1000, 5000);
        compare(w.liveMbps, 0);
        compare(w.avgMbps, 0);
    }

    function test_second_sample_computes_live_and_avg() {
        var w = SpeedTest.initWindow();
        w = SpeedTest.addSample(w, 0, 0);
        // +1,000,000 bytes over 1000ms = 8 Mbps, live and avg agree on the
        // second sample (the window so far is just the one interval).
        w = SpeedTest.addSample(w, 1000, 1000000);
        compare(w.liveMbps, 8);
        compare(w.avgMbps, 8);
    }

    function test_avg_covers_whole_window_not_just_last_tick() {
        var w = SpeedTest.initWindow();
        w = SpeedTest.addSample(w, 0, 0);
        w = SpeedTest.addSample(w, 1000, 1000000); // fast first second: 8 Mbps
        w = SpeedTest.addSample(w, 2000, 1125000); // slow second second: 1 Mbps
        compare(w.liveMbps, 1);
        // whole window: 1,125,000 bytes over 2000ms = 4.5 Mbps.
        compare(w.avgMbps, 4.5);
    }

    function test_counter_reset_mid_window_reads_live_zero() {
        var w = SpeedTest.initWindow();
        w = SpeedTest.addSample(w, 0, 5000000);
        w = SpeedTest.addSample(w, 1000, 4000000); // counter went backwards
        compare(w.liveMbps, 0);
        compare(w.avgMbps, 0);
    }

    function test_zero_duration_between_samples_reads_zero() {
        var w = SpeedTest.initWindow();
        w = SpeedTest.addSample(w, 1000, 0);
        w = SpeedTest.addSample(w, 1000, 500000); // same timestamp twice
        compare(w.liveMbps, 0);
    }

    // parseIface

    function test_parseIface_from_real_route_get_shape() {
        compare(SpeedTest.parseIface("1.1.1.1 via 10.0.2.2 dev eth0 src 10.0.2.15 uid 0 \n    cache"), "eth0");
    }

    function test_parseIface_missing_dev_token_is_null() {
        compare(SpeedTest.parseIface("RTNETLINK answers: Network is unreachable"), null);
    }

    function test_parseIface_empty_output_is_null() {
        compare(SpeedTest.parseIface(""), null);
        compare(SpeedTest.parseIface(null), null);
    }

    // parseStatBytes

    function test_parseStatBytes_normal_two_lines() {
        var s = SpeedTest.parseStatBytes("123456\n789012\n");
        compare(s.rx, 123456);
        compare(s.tx, 789012);
    }

    function test_parseStatBytes_missing_line_is_null() {
        compare(SpeedTest.parseStatBytes("123456\n"), null);
    }

    function test_parseStatBytes_empty_is_null() {
        compare(SpeedTest.parseStatBytes(""), null);
        compare(SpeedTest.parseStatBytes(null), null);
    }

    function test_parseStatBytes_non_numeric_is_null() {
        compare(SpeedTest.parseStatBytes("cat: No such file or directory\ncat: No such file or directory\n"), null);
    }
}
