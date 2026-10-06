//! Reminder model: duration parsing, entry shape, the due split, and every
//! label the bar cell, summary notification and IPC reply render. The clock
//! is always a `now_ms` argument and nothing mutates its input.
//!
//! Times are milliseconds since the epoch, held as `f64` because state.json is
//! user-editable and may carry any finite number.

use std::sync::LazyLock;

use chrono::{DateTime, Local, TimeZone, Timelike};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::js;

pub const MAX_DURATION_SECONDS: u64 = 30 * 24 * 60 * 60;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub message: String,
    pub set_at: f64,
    pub due_at: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Spec {
    pub seconds: u64,
    pub message: String,
}

/// Seconds, or `None` when the whole string is not a duration. Whitespace is
/// illegal here by design: `parse_spec` has already split the duration off
/// the message before this runs, so a space inside the duration token itself
/// is a typo, not a separator.
///
/// The first token's bare number is minutes ("10" is ten minutes), and a
/// later bare number drops to the next smaller unit ("1h30" is 90 minutes,
/// "5m30" is 5m30s). A bare number after seconds is a parse failure rather
/// than a silent reinterpretation.
pub fn parse_duration(text: &str) -> Option<u64> {
    static TOKEN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"([0-9]+)([hms]?)").unwrap());
    let s = js::trim(text).to_lowercase();
    if s.is_empty() || s.chars().any(js::is_space) {
        return None;
    }

    let mut cursor = 0;
    let mut total: u64 = 0;
    let mut prev = "";
    for m in TOKEN.captures_iter(&s) {
        let whole = m.get(0).unwrap();
        // Every token must butt against the previous one: anything the
        // grammar does not cover (a sign, a stray letter) shows up as a gap.
        if whole.start() != cursor {
            return None;
        }
        cursor = whole.end();

        let unit = match &m[2] {
            "" => match prev {
                "" | "h" => "m",
                "m" => "s",
                _ => return None,
            },
            "h" => "h",
            "m" => "m",
            _ => "s",
        };
        let per_unit = match unit {
            "h" => 3600,
            "m" => 60,
            _ => 1,
        };
        let n: u64 = m[1].parse().unwrap_or(u64::MAX);
        total = total.saturating_add(n.saturating_mul(per_unit));
        prev = unit;
    }

    if cursor != s.len() || total == 0 || total > MAX_DURATION_SECONDS {
        return None;
    }
    Some(total)
}

/// "25m coffee break" gives 1500 seconds and "coffee break". Splits on the
/// first run of whitespace: first token is the duration, the rest is the
/// message verbatim. This is the shape the menu's single input field and
/// `reminder set` both produce.
pub fn parse_spec(text: &str) -> Option<Spec> {
    let s = js::trim(text);
    if s.is_empty() {
        return None;
    }
    let split = s.find(js::is_space);
    let seconds = parse_duration(&s[..split.unwrap_or(s.len())])?;
    Some(Spec {
        seconds,
        message: split.map_or(String::new(), |i| js::trim(&s[i..]).to_owned()),
    })
}

/// The id is an opaque string, never parsed downstream. `serial` only
/// separates two reminders set within the same millisecond.
pub fn make_entry(seconds: u64, message: &str, now_ms: f64, serial: u64) -> Entry {
    Entry {
        id: format!("rem-{}-{serial}", js::num_to_string(now_ms)),
        message: message.to_owned(),
        set_at: now_ms,
        due_at: now_ms + seconds as f64 * 1000.0,
    }
}

fn by_due_at(a: &Entry, b: &Entry) -> std::cmp::Ordering {
    a.due_at.partial_cmp(&b.due_at).unwrap_or(std::cmp::Ordering::Equal)
}

/// Sorted ascending by `due_at`, which is what lets `bar_label` and `due`
/// read the soonest entry off the front instead of scanning.
pub fn add(list: &[Entry], entry: Entry) -> Vec<Entry> {
    let mut next = list.to_vec();
    next.push(entry);
    next.sort_by(by_due_at);
    next
}

/// state.json is a user-editable file the shell only reads, so an arbitrary
/// value can arrive here: anything without a usable id and dueAt is dropped
/// rather than rendered as a broken row.
pub fn normalize(raw: &Value) -> Vec<Entry> {
    let Some(items) = raw.as_array() else {
        return Vec::new();
    };
    let mut list: Vec<Entry> = items
        .iter()
        .filter_map(|e| {
            let obj = e.as_object()?;
            let id = obj.get("id")?.as_str().filter(|s| !s.is_empty())?;
            let due_at = js::finite_number(obj.get("dueAt"))?;
            Some(Entry {
                id: id.to_owned(),
                message: js::str_of(obj.get("message")),
                set_at: js::finite_number(obj.get("setAt")).unwrap_or(due_at),
                due_at,
            })
        })
        .collect();
    list.sort_by(by_due_at);
    list
}

#[derive(Clone, Debug, PartialEq)]
pub struct Due {
    pub fired: Vec<Entry>,
    /// Equal to the input list when nothing fired: the service skips its
    /// state.json write on every one of its 1s ticks on `fired.is_empty()`.
    /// An entry whose `due_at` passed while the shell was down is treated
    /// exactly like one that just crossed, so it fires on the first tick
    /// after state.json loads (late beats silently dropped).
    pub remaining: Vec<Entry>,
}

pub fn due(list: &[Entry], now_ms: f64) -> Due {
    let (fired, remaining): (Vec<Entry>, Vec<Entry>) =
        list.iter().cloned().partition(|e| e.due_at <= now_ms);
    Due {
        remaining: if fired.is_empty() { list.to_vec() } else { remaining },
        fired,
    }
}

/// Rounded up so a still-pending reminder never displays 00:00, which would
/// read as already fired.
pub fn remaining_seconds(entry: &Entry, now_ms: f64) -> f64 {
    ((entry.due_at - now_ms) / 1000.0).ceil().max(0.0)
}

/// Width is stability-driven (a countdown is a numeric display that must not
/// jitter): always two-digit minutes below an hour, widening exactly once at
/// the hour boundary.
pub fn countdown_label(seconds: f64) -> String {
    let total = seconds.floor().max(0.0) as u64;
    let hours = total / 3600;
    let minutes = (total % 3600) / 60;
    let secs = total % 60;
    if hours > 0 {
        format!("{hours}:{minutes:02}:{secs:02}")
    } else {
        format!("{minutes:02}:{secs:02}")
    }
}

/// The bar cell's text: soonest countdown alone, or fused with the count via
/// the spaced slash for meta pairs. `list[0]` is the soonest because `add` and
/// `normalize` both keep the list sorted.
pub fn bar_label(list: &[Entry], now_ms: f64) -> String {
    let Some(first) = list.first() else {
        return String::new();
    };
    let soonest = countdown_label(remaining_seconds(first, now_ms));
    if list.len() == 1 {
        soonest
    } else {
        format!("{soonest} / {}", list.len())
    }
}

pub fn summary_lines(list: &[Entry], now_ms: f64) -> Vec<String> {
    list.iter()
        .map(|e| format!("{} / {}", e.message, countdown_label(remaining_seconds(e, now_ms))))
        .collect()
}

/// 24h wall clock in the local timezone, for callers that confirm when a
/// reminder lands rather than counting down to it.
pub fn due_clock(due_at_ms: f64) -> String {
    let when: DateTime<Local> = Local
        .timestamp_millis_opt(due_at_ms as i64)
        .earliest()
        .unwrap_or_default();
    format!("{:02}:{:02}", when.hour(), when.minute())
}
