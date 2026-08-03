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
}
