//! Year-elapsed and life-lived fractions. `now` is always an argument.

use chrono::{DateTime, Datelike, NaiveDate, TimeZone};

use fs_js as js;

fn utc_jan_first_ms(year: i32) -> Option<i64> {
    Some(
        NaiveDate::from_ymd_opt(year, 1, 1)?
            .and_hms_opt(0, 0, 0)?
            .and_utc()
            .timestamp_millis(),
    )
}

fn fraction(now_ms: i64, start: i64, end: i64) -> f64 {
    ((now_ms - start) as f64 / (end - start) as f64).clamp(0.0, 1.0)
}

/// 0..1 fraction of the current calendar year elapsed. The year is the one
/// `now` reads in its own zone, the bounds are UTC, so a leap year's Feb 29
/// widens the denominator to 366 days without any day-counting of our own.
pub fn year_fraction<Tz: TimeZone>(now: &DateTime<Tz>) -> f64 {
    let year = now.year();
    match (utc_jan_first_ms(year), utc_jan_first_ms(year + 1)) {
        (Some(start), Some(end)) => fraction(now.timestamp_millis(), start, end),
        _ => 0.0,
    }
}

/// 0..1 fraction of an assumed lifespan lived, or `None` when birth year or
/// life expectancy is missing or outside a sane human range: the easter egg
/// must never render a wrong bar off garbage input.
pub fn life_fraction<Tz: TimeZone>(
    now: &DateTime<Tz>,
    birth_year: Option<f64>,
    life_expectancy: Option<f64>,
) -> Option<f64> {
    let birth = birth_year.filter(|v| v.is_finite())?;
    let life = life_expectancy.filter(|v| v.is_finite())?;
    if birth < 1900.0 || birth > f64::from(now.year()) {
        return None;
    }
    if life <= 0.0 || life > 130.0 {
        return None;
    }
    // Date.UTC truncates a fractional year.
    let start = utc_jan_first_ms(birth.trunc() as i32)?;
    let end = utc_jan_first_ms((birth + life).trunc() as i32)?;
    Some(fraction(now.timestamp_millis(), start, end))
}

pub fn format_percent(fraction: f64) -> String {
    format!("{}%", js::round(fraction * 100.0) as i64)
}

/// Settings (`calendar.birthYear`/`calendar.lifeExpectancy`) declaratively
/// override the runtime state value when present; state.json's own value
/// (written by the life-progress easter egg) is the fallback when settings
/// is silent, never the other way around.
pub fn resolve_override<T>(settings: Option<T>, state: Option<T>) -> Option<T> {
    settings.or(state)
}
