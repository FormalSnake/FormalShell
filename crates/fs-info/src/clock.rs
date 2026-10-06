//! Date-format math for the bar clock and the calendar panel. The renderer
//! turns a ring entry into text with the toolkit's own date formatter; this
//! module only picks the entry and resolves what that formatter lacks.

use chrono::{Datelike, NaiveDate};

use fs_js as js;

/// Right-click on the bar clock walks this ring in order. Each 24-hour
/// preset sits next to its 12-hour twin so one more click swaps notation
/// without walking the whole ring; the ISO-week preset has no twin of its
/// own since ISO 8601 always writes time on a 24-hour clock.
pub const CLOCK_FORMATS: [&str; 6] = [
    "hh:mm",
    "h:mm AP",
    "ddd hh:mm",
    "ddd d MMM hh:mm",
    "yyyy-MM-dd hh:mm",
    "d MMM 'W'ww",
];

pub fn formats() -> Vec<&'static str> {
    CLOCK_FORMATS.to_vec()
}

pub fn pad2(n: i64) -> String {
    format!("{}{n}", if n < 10 { "0" } else { "" })
}

/// ISO-8601 week number: the week owning the Thursday of the date's
/// Monday-based week.
pub fn iso_week(date: NaiveDate) -> u32 {
    date.iso_week().week()
}

/// Every "ww" in `format` becomes the zero-padded ISO week for `date`,
/// ahead of the toolkit formatter: it has no ISO-week specifier, and none
/// of its recognized tokens are digits, so a plain substitution is safe to
/// run first.
pub fn substitute_iso_week(format: &str, date: NaiveDate) -> String {
    format.replace("ww", &pad2(i64::from(iso_week(date))))
}

/// The rendered clock split into upright lines for a vertical bar, which has
/// no room to run one across it. Every separator the ring's own presets use
/// (the colon between hours and minutes, the spaces between fields, the
/// dashes in the ISO date) becomes a line break, so each line is a whole
/// field: `09:41` stacks as `09` over `41`, never a hard wrap mid-number.
pub fn stacked_lines(text: &str) -> Vec<String> {
    text.split(|c: char| js::is_space(c) || c == ':' || c == '-')
        .filter(|part| !part.is_empty())
        .map(str::to_owned)
        .collect()
}

/// Which notation a ring entry writes. Every 12-hour preset is its 24-hour
/// neighbour's twin with the AP specifier added, so the agenda reads the
/// live format here rather than carrying a second notation setting.
pub fn uses_meridiem(format: &str) -> bool {
    format.contains("AP") || format.contains("ap")
}

/// The entry after `current`. A format that isn't in the ring (hand-edited
/// state.json, an old preset dropped from a later release) starts the walk
/// at the top rather than failing.
pub fn next_format(current: &str) -> &'static str {
    let next = CLOCK_FORMATS
        .iter()
        .position(|f| *f == current)
        .map_or(0, |i| (i + 1) % CLOCK_FORMATS.len());
    CLOCK_FORMATS[next]
}
