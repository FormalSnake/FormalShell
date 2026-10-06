use chrono::{DateTime, TimeZone, Utc};
use fs_info::calendar::progress::*;

fn utc(y: i32, m: u32, d: u32, h: u32, mi: u32) -> DateTime<Utc> {
    Utc.with_ymd_and_hms(y, m, d, h, mi, 0).unwrap()
}

fn near(actual: f64, expected: f64) -> bool {
    (actual - expected).abs() < 1e-9
}

#[test]
fn year_fraction_at_start_of_year_is_zero() {
    assert_eq!(year_fraction(&utc(2026, 1, 1, 0, 0)), 0.0);
}

#[test]
fn year_fraction_at_midyear_is_about_half() {
    let f = year_fraction(&utc(2026, 7, 2, 12, 0));
    assert!(f > 0.49 && f < 0.51);
}

#[test]
fn year_fraction_stays_below_one_at_end_of_year() {
    let f = year_fraction(&utc(2026, 12, 31, 23, 59));
    assert!(f > 0.99 && f < 1.0);
}

#[test]
fn year_fraction_leap_year_has_366_day_denominator() {
    // Dec 31 00:00 is the START of the last day: 365 full days elapsed in a
    // leap (366-day) year, 364 in a non-leap (365-day) year.
    let leap = year_fraction(&utc(2028, 12, 31, 0, 0));
    let non_leap = year_fraction(&utc(2026, 12, 31, 0, 0));
    assert!(near(leap, 365.0 / 366.0));
    assert!(near(non_leap, 364.0 / 365.0));
}

#[test]
fn year_fraction_clamped_to_0_1_range() {
    let f = year_fraction(&utc(2026, 7, 1, 0, 0));
    assert!((0.0..=1.0).contains(&f));
}

#[test]
fn life_fraction_at_birth_is_zero() {
    assert_eq!(life_fraction(&utc(2000, 1, 1, 0, 0), Some(2000.0), Some(80.0)), Some(0.0));
}

#[test]
fn life_fraction_at_half_expectancy_is_about_half() {
    let f = life_fraction(&utc(2040, 1, 1, 0, 0), Some(2000.0), Some(80.0)).unwrap();
    assert!(f > 0.49 && f < 0.51);
}

#[test]
fn life_fraction_past_expectancy_clamps_to_one() {
    assert_eq!(life_fraction(&utc(2100, 1, 1, 0, 0), Some(2000.0), Some(80.0)), Some(1.0));
}

#[test]
fn life_fraction_null_when_birth_year_missing() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), None, Some(80.0)), None);
}

#[test]
fn life_fraction_null_when_life_expectancy_missing() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(2000.0), None), None);
}

#[test]
fn life_fraction_null_when_birth_year_in_future() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(2200.0), Some(80.0)), None);
}

#[test]
fn life_fraction_null_when_birth_year_absurdly_old() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(1800.0), Some(80.0)), None);
}

#[test]
fn life_fraction_null_when_life_expectancy_absurd() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(2000.0), Some(500.0)), None);
}

#[test]
fn life_fraction_null_when_life_expectancy_zero_or_negative() {
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(2000.0), Some(0.0)), None);
    assert_eq!(life_fraction(&utc(2026, 1, 1, 0, 0), Some(2000.0), Some(-5.0)), None);
}

#[test]
fn format_percent_rounds_to_whole_number() {
    assert_eq!(format_percent(0.426), "43%");
}

#[test]
fn format_percent_zero() {
    assert_eq!(format_percent(0.0), "0%");
}

#[test]
fn format_percent_one() {
    assert_eq!(format_percent(1.0), "100%");
}

#[test]
fn resolve_override_prefers_settings_when_present() {
    assert_eq!(resolve_override(Some(1990), Some(1985)), Some(1990));
}

#[test]
fn resolve_override_settings_zero_counts_as_present() {
    assert_eq!(resolve_override(Some(0), Some(1985)), Some(0));
}

#[test]
fn resolve_override_falls_back_to_state_when_settings_absent() {
    // `undefined` and `null` both read as `None`.
    assert_eq!(resolve_override(None, Some(1985)), Some(1985));
}

#[test]
fn resolve_override_none_when_both_absent() {
    assert_eq!(resolve_override::<i32>(None, None), None);
}
