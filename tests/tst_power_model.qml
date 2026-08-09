import QtQuick
import QtTest
import "../shell/Power/model.js" as Power

TestCase {
    name: "PowerModel"

    // warnEvent

    function test_boot_below_warn_fires_immediately() {
        var r = Power.warnEvent(null, 8, false, Power.initialFired());
        compare(r.event, "warn");
        compare(r.fired.warn, true);
        compare(r.fired.critical, false);
    }

    function test_boot_below_critical_fires_critical_only() {
        var r = Power.warnEvent(null, 3, false, Power.initialFired());
        compare(r.event, "critical");
        compare(r.fired.warn, true);
        compare(r.fired.critical, true);
    }

    function test_crossing_fires_warn_once() {
        var fired = Power.initialFired();
        var r1 = Power.warnEvent(15, 9, false, fired);
        compare(r1.event, "warn");
        fired = r1.fired;

        var r2 = Power.warnEvent(9, 9, false, fired);
        compare(r2.event, null);
        compare(r2.fired.warn, true);
    }

    function test_crossing_fires_critical_after_warn() {
        var fired = Power.initialFired();
        var r1 = Power.warnEvent(15, 9, false, fired);
        fired = r1.fired;

        var r2 = Power.warnEvent(9, 4, false, fired);
        compare(r2.event, "critical");
        compare(r2.fired.warn, true);
        compare(r2.fired.critical, true);
    }

    function test_single_tick_below_both_fires_critical_not_warn() {
        var r = Power.warnEvent(50, 2, false, Power.initialFired());
        compare(r.event, "critical");
        compare(r.fired.warn, true);
        compare(r.fired.critical, true);
    }

    function test_rearm_on_charge_clears_both_flags() {
        var fired = { warn: true, critical: true };
        var r = Power.warnEvent(4, 4, true, fired);
        compare(r.event, null);
        compare(r.fired.warn, false);
        compare(r.fired.critical, false);
    }

    function test_charge_interruption_refires_warn() {
        var fired = Power.initialFired();
        var r1 = Power.warnEvent(15, 9, false, fired);
        fired = r1.fired;

        var r2 = Power.warnEvent(9, 9, true, fired); // brief plug-in
        fired = r2.fired;
        compare(fired.warn, false);

        var r3 = Power.warnEvent(9, 9, false, fired); // unplugged, still low
        compare(r3.event, "warn");
    }

    function test_no_refire_while_still_low_without_recharge() {
        var fired = Power.initialFired();
        var r1 = Power.warnEvent(15, 9, false, fired);
        fired = r1.fired;

        var r2 = Power.warnEvent(9, 8, false, fired);
        compare(r2.event, null);

        var r3 = Power.warnEvent(8, 9, false, r2.fired); // ticks back up, no recharge
        compare(r3.event, null);
        compare(r3.fired.warn, true);
    }

    function test_rising_reading_does_not_fire() {
        // Re-armed (post-charge) but the very next reading upticks before
        // resuming its real discharge — must not fire on that single blip.
        var fired = Power.initialFired();
        var r = Power.warnEvent(8, 10, false, fired);
        compare(r.event, null);
        compare(r.fired.warn, false);
    }

    function test_custom_thresholds_respected() {
        var r = Power.warnEvent(null, 25, false, Power.initialFired(), 30, 15);
        compare(r.event, "warn");
    }

    function test_above_thresholds_never_fires() {
        var r = Power.warnEvent(50, 45, false, Power.initialFired());
        compare(r.event, null);
        compare(r.fired.warn, false);
        compare(r.fired.critical, false);
    }

    // formatDuration

    function test_format_duration_minutes_only() {
        compare(Power.formatDuration(14 * 60), "14M");
    }

    function test_format_duration_hours_and_minutes() {
        compare(Power.formatDuration(2 * 3600 + 14 * 60), "2H 14M");
    }

    function test_format_duration_days_and_hours() {
        compare(Power.formatDuration(27 * 3600), "1D 3H");
    }

    function test_format_duration_zero() {
        compare(Power.formatDuration(0), "0M");
    }

    // formatRate

    function test_format_rate_positive() {
        compare(Power.formatRate(12.34), "12.3W");
    }

    function test_format_rate_negative_shows_magnitude() {
        compare(Power.formatRate(-8.05), "8.1W");
    }

    // staticFieldsVisible

    function test_static_fields_hidden_while_motion_enabled_and_rotating() {
        compare(Power.staticFieldsVisible(true, true), false);
    }

    function test_static_fields_shown_when_motion_disabled_even_if_rotating() {
        compare(Power.staticFieldsVisible(false, true), true);
    }

    function test_static_fields_shown_when_not_rotating_even_with_motion_enabled() {
        compare(Power.staticFieldsVisible(true, false), true);
    }

    function test_static_fields_shown_when_motion_disabled_and_not_rotating() {
        compare(Power.staticFieldsVisible(false, false), true);
    }

    // raplDeltaUj

    function test_rapl_delta_normal_increase() {
        compare(Power.raplDeltaUj(1000000, 1500000, 65000000), 500000);
    }

    function test_rapl_delta_wraps_at_max_range() {
        // counter was near the top, wrapped back to a small value.
        compare(Power.raplDeltaUj(64900000, 100000, 65000000), 200000);
    }

    // raplWatts

    function test_rapl_watts_normal_sample() {
        // 1,000,000 uJ over 1000ms = 1 W.
        compare(Power.raplWatts(0, 1000000, 65000000, 1000), 1);
    }

    function test_rapl_watts_matches_e1504g_probe() {
        // e1504g probe (plan header): ~8.5W package draw over a 2s interval.
        compare(Power.raplWatts(0, 17000000, 65000000, 2000), 8.5);
    }

    function test_rapl_watts_zero_interval_is_null() {
        compare(Power.raplWatts(0, 1000000, 65000000, 0), null);
    }

    function test_rapl_watts_negative_interval_is_null() {
        compare(Power.raplWatts(0, 1000000, 65000000, -50), null);
    }

    function test_rapl_watts_wraparound_end_to_end() {
        // 200,000 uJ over 500ms = 0.4 W, computed through the wrap.
        compare(Power.raplWatts(64900000, 100000, 65000000, 500), 0.4);
    }

    // parseRaplUj

    function test_parseRaplUj_normal_two_lines() {
        var r = Power.parseRaplUj("12345678\n65000000\n");
        compare(r.energyUj, 12345678);
        compare(r.maxRangeUj, 65000000);
    }

    function test_parseRaplUj_permission_denied_leaves_one_line() {
        // `cat energy_uj max_energy_range_uj` when energy_uj is root-only:
        // stderr carries the "Permission denied" line, stdout only gets
        // max_energy_range_uj's own content — one line, honest null.
        compare(Power.parseRaplUj("65000000\n"), null);
    }

    function test_parseRaplUj_empty_is_null() {
        compare(Power.parseRaplUj(""), null);
        compare(Power.parseRaplUj(null), null);
    }

    function test_parseRaplUj_zero_max_range_is_null() {
        compare(Power.parseRaplUj("12345\n0\n"), null);
    }

    function test_parseRaplUj_non_numeric_is_null() {
        compare(Power.parseRaplUj("cat: Permission denied\ncat: Permission denied\n"), null);
    }

    // formatWattageRow

    function test_wattage_row_charging_no_cpu() {
        compare(Power.formatWattageRow(true, 15.5, null), "CHARGING 15.5W");
    }

    function test_wattage_row_discharging_no_cpu() {
        compare(Power.formatWattageRow(false, -12.3, null), "DRAW 12.3W");
    }

    function test_wattage_row_charging_with_cpu() {
        compare(Power.formatWattageRow(true, 15.5, 8.5), "CHARGING 15.5W / CPU 8.5W");
    }

    function test_wattage_row_discharging_with_cpu() {
        compare(Power.formatWattageRow(false, -12.3, 8.5), "DRAW 12.3W / CPU 8.5W");
    }

    function test_wattage_row_cpu_undefined_omits_half() {
        compare(Power.formatWattageRow(true, 15.5, undefined), "CHARGING 15.5W");
    }
}
