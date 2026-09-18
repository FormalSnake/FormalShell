import QtQuick
import QtTest
import "../shell/Theme/sun.js" as Sun

TestCase {
    name: "Sun"

    // Expected pairs from open-meteo's own daily sunrise/sunset (the same
    // service shell/Weather reads), queried per case:
    // https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&timezone=..&daily=sunrise,sunset
    // Three minutes of tolerance: the formula evaluates the sun's
    // declination at local midnight rather than at the crossing itself,
    // which is the reference implementation's own simplification.
    readonly property int toleranceMinutes: 3

    function _minutes(hh, mm) {
        return hh * 60 + mm;
    }

    function _closeTo(actual, expected) {
        return Math.abs(actual - expected) <= toleranceMinutes;
    }

    // sunTimes, against published pairs

    // Greenwich, 2026-09-22 (September equinox), UTC: 05:45 / 17:58.
    function test_sun_times_greenwich_equinox() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 8, 22, 12)), 51.4779, -0.0015, 0);
        compare(t.polar, "");
        verify(_closeTo(t.sunriseMinutes, _minutes(5, 45)));
        verify(_closeTo(t.sunsetMinutes, _minutes(17, 58)));
    }

    // Stockholm, 2026-06-21 (June solstice), read in UTC: 01:30 / 20:08.
    function test_sun_times_high_latitude_summer() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 59.3293, 18.0686, 0);
        compare(t.polar, "");
        verify(_closeTo(t.sunriseMinutes, _minutes(1, 30)));
        verify(_closeTo(t.sunsetMinutes, _minutes(20, 8)));
    }

    // Sydney, 2026-07-15 (southern winter), in its own +10: 06:58 / 17:04.
    function test_sun_times_southern_hemisphere_winter() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 6, 15, 12)), -33.8688, 151.2093, 10);
        compare(t.polar, "");
        verify(_closeTo(t.sunriseMinutes, _minutes(6, 58)));
        verify(_closeTo(t.sunsetMinutes, _minutes(17, 4)));
    }

    // A pair whose solar noon sits near the edge of the zone's day runs off
    // it: Sydney read in UTC rises at 20:57 the day before.
    function test_sun_times_can_fall_outside_the_day() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 6, 15, 12)), -33.8688, 151.2093, 0);
        verify(t.sunriseMinutes < 0);
        compare(Sun.hhmm(t.sunriseMinutes), "20:58");
    }

    // Longyearbyen at the June solstice: open-meteo answers a sunset a full
    // day after the sunrise, the midnight sun.
    function test_sun_times_polar_day() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 78.2232, 15.6469, 0);
        compare(t.polar, "day");
        compare(t.sunriseMinutes, null);
        compare(t.sunsetMinutes, null);
    }

    // Concordia station at the same solstice: open-meteo answers a
    // zero-length day.
    function test_sun_times_polar_night() {
        var t = Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), -75.1, 123.33, 0);
        compare(t.polar, "night");
        compare(t.sunriseMinutes, null);
    }

    function test_sun_times_null_for_out_of_range_latitude() {
        compare(Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 91, 0, 0), null);
    }

    function test_sun_times_null_for_out_of_range_longitude() {
        compare(Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 0, -181, 0), null);
    }

    function test_sun_times_null_for_non_number_coordinates() {
        compare(Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), "52", 13, 0), null);
        compare(Sun.sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 52, NaN, 0), null);
    }

    // The offset left out is the date's own, so a pair asked for without one
    // reads as wall clock on the machine running this.
    function test_sun_times_defaults_to_the_local_offset() {
        var date = new Date(Date.UTC(2026, 5, 21, 12));
        var local = Sun.sunTimes(date, 59.3293, 18.0686);
        var utc = Sun.sunTimes(date, 59.3293, 18.0686, 0);
        var offset = -date.getTimezoneOffset() / 60;
        verify(Math.abs((local.sunriseMinutes - utc.sunriseMinutes) - offset * 60) < 1);
    }

    // fallbackDark, the 20:00 to 06:00 window

    function test_fallback_dark_window_edges() {
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 19, 59)), false);
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 20, 0)), true);
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 5, 59)), true);
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 6, 0)), false);
    }

    function test_fallback_dark_across_midnight() {
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 23, 30)), true);
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 0, 30)), true);
        compare(Sun.fallbackDark(new Date(2026, 8, 22, 12, 0)), false);
    }

    // isDark

    function _times(sunriseMinutes, sunsetMinutes) {
        return {
            latitude: 51.4779,
            longitude: -0.0015,
            tzOffsetHours: -(new Date(2026, 8, 22)).getTimezoneOffset() / 60,
            polar: "",
            sunriseMinutes: sunriseMinutes,
            sunsetMinutes: sunsetMinutes
        };
    }

    function test_is_dark_between_sunset_and_sunrise() {
        var t = _times(6 * 60, 18 * 60);
        compare(Sun.isDark(new Date(2026, 8, 22, 5, 59), t), true);
        compare(Sun.isDark(new Date(2026, 8, 22, 6, 0), t), false);
        compare(Sun.isDark(new Date(2026, 8, 22, 17, 59), t), false);
        compare(Sun.isDark(new Date(2026, 8, 22, 18, 0), t), true);
    }

    function test_is_dark_polar() {
        var night = { polar: "night", sunriseMinutes: null, sunsetMinutes: null };
        var day = { polar: "day", sunriseMinutes: null, sunsetMinutes: null };
        compare(Sun.isDark(new Date(2026, 8, 22, 12), night), true);
        compare(Sun.isDark(new Date(2026, 8, 22, 12), day), false);
        compare(Sun.isDark(new Date(2026, 8, 22, 2), day), false);
    }

    function test_is_dark_without_times_takes_the_fallback_window() {
        compare(Sun.isDark(new Date(2026, 8, 22, 21), null), true);
        compare(Sun.isDark(new Date(2026, 8, 22, 12), null), false);
    }

    // nextChange

    function test_next_change_before_sunrise_is_sunrise() {
        var next = Sun.nextChange(new Date(2026, 8, 22, 3), _times(6 * 60, 18 * 60));
        compare(next.getHours(), 6);
        compare(next.getMinutes(), 0);
        compare(next.getDate(), 22);
    }

    function test_next_change_during_the_day_is_sunset() {
        var next = Sun.nextChange(new Date(2026, 8, 22, 10), _times(6 * 60, 18 * 60));
        compare(next.getHours(), 18);
        compare(next.getDate(), 22);
    }

    // Past sunset the pair for today has nothing left to say, so the next
    // change is recomputed off the coordinates it carries.
    function test_next_change_after_sunset_is_tomorrows_sunrise() {
        var now = new Date(2026, 8, 22, 23);
        var next = Sun.nextChange(now, _times(6 * 60, 18 * 60));
        compare(next.getDate(), 23);
        verify(next.getTime() > now.getTime());
        var tomorrow = Sun.sunTimes(new Date(2026, 8, 23, 12), 51.4779, -0.0015);
        verify(Math.abs(next.getHours() * 60 + next.getMinutes() - tomorrow.sunriseMinutes) < 1);
    }

    function test_next_change_polar_is_local_midnight() {
        var next = Sun.nextChange(new Date(2026, 8, 22, 14), { polar: "day", sunriseMinutes: null, sunsetMinutes: null });
        compare(next.getDate(), 23);
        compare(next.getHours(), 0);
        compare(next.getMinutes(), 0);
    }

    function test_next_change_without_times_walks_the_fallback_window() {
        var morning = Sun.nextChange(new Date(2026, 8, 22, 3), null);
        compare(morning.getHours(), 6);
        compare(morning.getDate(), 22);
        var noon = Sun.nextChange(new Date(2026, 8, 22, 12), null);
        compare(noon.getHours(), 20);
        compare(noon.getDate(), 22);
        var night = Sun.nextChange(new Date(2026, 8, 22, 23), null);
        compare(night.getHours(), 6);
        compare(night.getDate(), 23);
    }

    // effectiveMode, every branch

    function test_effective_mode_pinned_keys() {
        compare(Sun.effectiveMode("dark", new Date(2026, 8, 22, 12), null, null), "dark");
        compare(Sun.effectiveMode("light", new Date(2026, 8, 22, 23), null, null), "light");
    }

    function test_effective_mode_manual_key_leaves_the_mode_alone() {
        compare(Sun.effectiveMode("", new Date(2026, 8, 22, 12), null, null), null);
        compare(Sun.effectiveMode("sunset-to-sunrise", new Date(2026, 8, 22, 12), null, null), null);
    }

    function test_effective_mode_auto_reads_the_schedule() {
        var t = _times(6 * 60, 18 * 60);
        compare(Sun.effectiveMode("auto", new Date(2026, 8, 22, 12), t, null), "light");
        compare(Sun.effectiveMode("auto", new Date(2026, 8, 22, 19), t, null), "dark");
    }

    function test_effective_mode_auto_without_location_reads_the_fallback() {
        compare(Sun.effectiveMode("auto", new Date(2026, 8, 22, 21), null, null), "dark");
        compare(Sun.effectiveMode("auto", new Date(2026, 8, 22, 7), null, null), "light");
    }

    function test_effective_mode_auto_override_wins_until_it_expires() {
        var t = _times(6 * 60, 18 * 60);
        var now = new Date(2026, 8, 22, 12);
        var live = { mode: "dark", untilMs: new Date(2026, 8, 22, 18).getTime() };
        compare(Sun.effectiveMode("auto", now, t, live), "dark");
        var expired = { mode: "dark", untilMs: new Date(2026, 8, 22, 11).getTime() };
        compare(Sun.effectiveMode("auto", now, t, expired), "light");
    }

    function test_effective_mode_auto_override_of_an_unknown_mode_reads_as_dark() {
        var live = { mode: "sepia", untilMs: new Date(2026, 8, 22, 18).getTime() };
        compare(Sun.effectiveMode("auto", new Date(2026, 8, 22, 12), _times(6 * 60, 18 * 60), live), "dark");
    }

    // hhmm

    function test_hhmm_formats_wall_clock() {
        compare(Sun.hhmm(0), "00:00");
        compare(Sun.hhmm(345.6), "05:46");
        compare(Sun.hhmm(1080), "18:00");
    }

    function test_hhmm_wraps_a_pair_outside_the_day() {
        compare(Sun.hhmm(-90), "22:30");
        compare(Sun.hhmm(1500), "01:00");
    }

    function test_hhmm_empty_for_no_time() {
        compare(Sun.hhmm(null), "");
        compare(Sun.hhmm(NaN), "");
    }
}
