import QtQuick
import QtTest
import "../shell/Calendar/progress.js" as Progress

TestCase {
    name: "CalendarProgress"

    function _utc(y, m, d, h, mi) {
        return new Date(Date.UTC(y, m, d, h || 0, mi || 0));
    }

    function _near(actual, expected) {
        return Math.abs(actual - expected) < 1e-9;
    }

    // yearFraction

    function test_year_fraction_at_start_of_year_is_zero() {
        compare(Progress.yearFraction(_utc(2026, 0, 1, 0, 0)), 0);
    }

    function test_year_fraction_at_midyear_is_about_half() {
        var f = Progress.yearFraction(_utc(2026, 6, 2, 12, 0));
        verify(f > 0.49 && f < 0.51);
    }

    function test_year_fraction_stays_below_one_at_end_of_year() {
        var f = Progress.yearFraction(_utc(2026, 11, 31, 23, 59));
        verify(f > 0.99 && f < 1);
    }

    function test_year_fraction_leap_year_has_366_day_denominator() {
        // Dec 31 00:00 is the START of the last day: 365 full days elapsed
        // in a leap (366-day) year, 364 in a non-leap (365-day) year.
        var leap = Progress.yearFraction(_utc(2028, 11, 31, 0, 0));
        var nonLeap = Progress.yearFraction(_utc(2026, 11, 31, 0, 0));
        verify(_near(leap, 365 / 366));
        verify(_near(nonLeap, 364 / 365));
    }

    function test_year_fraction_clamped_to_0_1_range() {
        var f = Progress.yearFraction(_utc(2026, 6, 1));
        verify(f >= 0 && f <= 1);
    }

    // lifeFraction

    function test_life_fraction_at_birth_is_zero() {
        compare(Progress.lifeFraction(_utc(2000, 0, 1), 2000, 80), 0);
    }

    function test_life_fraction_at_half_expectancy_is_about_half() {
        var f = Progress.lifeFraction(_utc(2040, 0, 1), 2000, 80);
        verify(f > 0.49 && f < 0.51);
    }

    function test_life_fraction_past_expectancy_clamps_to_one() {
        compare(Progress.lifeFraction(_utc(2100, 0, 1), 2000, 80), 1);
    }

    function test_life_fraction_null_when_birth_year_missing() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), undefined, 80), null);
    }

    function test_life_fraction_null_when_life_expectancy_missing() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 2000, undefined), null);
    }

    function test_life_fraction_null_when_birth_year_in_future() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 2200, 80), null);
    }

    function test_life_fraction_null_when_birth_year_absurdly_old() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 1800, 80), null);
    }

    function test_life_fraction_null_when_life_expectancy_absurd() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 2000, 500), null);
    }

    function test_life_fraction_null_when_life_expectancy_zero_or_negative() {
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 2000, 0), null);
        compare(Progress.lifeFraction(_utc(2026, 0, 1), 2000, -5), null);
    }

    // formatPercent

    function test_format_percent_rounds_to_whole_number() {
        compare(Progress.formatPercent(0.426), "43%");
    }

    function test_format_percent_zero() {
        compare(Progress.formatPercent(0), "0%");
    }

    function test_format_percent_one() {
        compare(Progress.formatPercent(1), "100%");
    }

    // resolveOverride

    function test_resolve_override_prefers_settings_when_present() {
        compare(Progress.resolveOverride(1990, 1985), 1990);
    }

    function test_resolve_override_settings_zero_counts_as_present() {
        compare(Progress.resolveOverride(0, 1985), 0);
    }

    function test_resolve_override_falls_back_to_state_when_settings_undefined() {
        compare(Progress.resolveOverride(undefined, 1985), 1985);
    }

    function test_resolve_override_falls_back_to_state_when_settings_null() {
        compare(Progress.resolveOverride(null, 1985), 1985);
    }

    function test_resolve_override_undefined_when_both_absent() {
        compare(Progress.resolveOverride(undefined, undefined), undefined);
    }
}
