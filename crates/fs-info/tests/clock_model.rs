use chrono::NaiveDate;
use fs_info::clock::*;

fn d(y: i32, m: u32, day: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, day).unwrap()
}

// Vectors cross-checked against Python's datetime.isocalendar().

#[test]
fn iso_week_year_start_on_thursday_is_week_one() {
    assert_eq!(iso_week(d(2026, 1, 1)), 1);
}

#[test]
fn iso_week_ordinary_date() {
    assert_eq!(iso_week(d(2026, 8, 17)), 34);
}

#[test]
fn iso_week_year_with_53_weeks() {
    assert_eq!(iso_week(d(2026, 12, 31)), 53);
}

#[test]
fn iso_week_jan_1_belongs_to_prior_year_week_53() {
    assert_eq!(iso_week(d(2005, 1, 1)), 53);
    assert_eq!(iso_week(d(2005, 1, 2)), 53);
}

#[test]
fn iso_week_dec_31_belongs_to_current_year() {
    assert_eq!(iso_week(d(2005, 12, 31)), 52);
}

#[test]
fn iso_week_dec_31_belongs_to_next_year_week_one() {
    assert_eq!(iso_week(d(2007, 12, 31)), 1);
}

#[test]
fn iso_week_jan_1_belongs_to_same_year_week_one() {
    assert_eq!(iso_week(d(2007, 1, 1)), 1);
    assert_eq!(iso_week(d(2008, 1, 1)), 1);
}

#[test]
fn iso_week_leading_days_before_first_thursday() {
    assert_eq!(iso_week(d(1977, 1, 1)), 53);
    assert_eq!(iso_week(d(1978, 1, 1)), 52);
    assert_eq!(iso_week(d(1978, 1, 2)), 1);
}

#[test]
fn pad2_single_digit() {
    assert_eq!(pad2(5), "05");
}

#[test]
fn pad2_double_digit() {
    assert_eq!(pad2(53), "53");
}

#[test]
fn substitute_iso_week_replaces_token() {
    assert_eq!(substitute_iso_week("d MMM 'W'ww", d(2026, 8, 17)), "d MMM 'W'34");
}

#[test]
fn substitute_iso_week_replaces_every_occurrence() {
    assert_eq!(substitute_iso_week("ww/ww", d(2026, 8, 17)), "34/34");
}

#[test]
fn substitute_iso_week_leaves_format_untouched_without_token() {
    assert_eq!(substitute_iso_week("hh:mm", d(2026, 8, 17)), "hh:mm");
}

#[test]
fn stacked_lines_break_the_time_into_upright_fields() {
    assert_eq!(stacked_lines("09:41"), ["09", "41"]);
    assert_eq!(stacked_lines("9:41 AM"), ["9", "41", "AM"]);
    assert_eq!(stacked_lines("Mon 09:41"), ["Mon", "09", "41"]);
}

#[test]
fn stacked_lines_break_an_iso_date_on_its_dashes() {
    assert_eq!(
        stacked_lines("2026-08-17 09:41"),
        ["2026", "08", "17", "09", "41"]
    );
}

#[test]
fn stacked_lines_drop_empty_pieces() {
    assert!(stacked_lines("").is_empty());
    assert_eq!(stacked_lines("  09 : 41  "), ["09", "41"]);
}

#[test]
fn every_preset_stacks_into_at_least_one_line() {
    for format in formats() {
        let rendered = substitute_iso_week(format, d(2026, 8, 17));
        assert!(!stacked_lines(&rendered).is_empty());
    }
}

#[test]
fn formats_returns_a_copy() {
    let mut a = formats();
    a.push("bogus");
    assert_eq!(formats().len(), CLOCK_FORMATS.len());
}

#[test]
fn next_format_walks_the_ring_in_order() {
    let ring = formats();
    for (i, f) in ring.iter().enumerate() {
        assert_eq!(next_format(f), ring[(i + 1) % ring.len()]);
    }
}

#[test]
fn next_format_wraps_from_last_to_first() {
    let ring = formats();
    assert_eq!(next_format(ring[ring.len() - 1]), ring[0]);
}

#[test]
fn next_format_unknown_current_starts_at_top() {
    assert_eq!(next_format("nonsense"), CLOCK_FORMATS[0]);
}

#[test]
fn uses_meridiem_reads_the_twelve_hour_presets() {
    assert!(uses_meridiem("h:mm AP"));
    assert!(uses_meridiem("h:mm ap"));
}

#[test]
fn uses_meridiem_is_false_for_every_other_preset() {
    for f in formats() {
        if f.contains("AP") || f.contains("ap") {
            continue;
        }
        assert!(!uses_meridiem(f), "{f}");
    }
}
