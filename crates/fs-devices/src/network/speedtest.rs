//! Pure math and parsing for the network speed test: flat ledger rows, no
//! gauges. The panel drives real `ip route get`, `cat
//! /sys/class/net/.../statistics/*` and `curl` processes and feeds their
//! output through these helpers. Ported from `shell/Network/speedtest.js`.

use std::sync::LazyLock;

use regex::Regex;

use fs_js::{self as js, SPACE};

/// bytesDelta/msDelta -> Mbps. A non-positive duration (two samples with the
/// same timestamp) and a non-positive delta (a counter reset, e.g. the
/// interface flapped mid-run, or rx/tx wrapped) both read as 0 rather than an
/// infinite or negative rate.
pub fn mbps(bytes_delta: f64, ms_delta: f64) -> f64 {
    if ms_delta.is_nan() || ms_delta <= 0.0 || bytes_delta.is_nan() || bytes_delta <= 0.0 {
        return 0.0;
    }
    (bytes_delta * 8.0) / ms_delta / 1000.0
}

/// `Number.prototype.toFixed(1)` for a positive value: exact binary value,
/// ties (only x.25 and x.75 can be exact ties) go up.
fn to_fixed_1(value: f64) -> String {
    let quarters = value * 4.0;
    let tie = quarters.fract() == 0.0 && quarters % 2.0 == 1.0;
    if tie {
        let tenths = (value * 10.0).floor() as u64 + 1;
        return format!("{}.{}", tenths / 10, tenths % 10);
    }
    format!("{value:.1}")
}

/// Sub-10 Mbps keeps one decimal (the range where a whole number would hide a
/// real difference), 10 and above rounds off.
pub fn format_mbps(value: f64) -> String {
    if value.is_nan() || value <= 0.0 {
        return "0.0".into();
    }
    if value < 10.0 {
        return to_fixed_1(value);
    }
    js::num_str(js::round(value))
}

pub const DEFAULT_MAX_MBPS: f64 = 1000.0;

/// Flat ledger fill fraction: current/expected-max, capped at 1 so a link
/// faster than the nominal scale never overruns the track.
pub fn fill_fraction(value: f64, max_mbps: Option<f64>) -> f64 {
    let max = match max_mbps {
        Some(m) if m > 0.0 => m,
        _ => DEFAULT_MAX_MBPS,
    };
    if value.is_nan() || value <= 0.0 {
        return 0.0;
    }
    (value / max).clamp(0.0, 1.0)
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Sample {
    pub t: f64,
    pub bytes: f64,
}

/// A running window over one phase (download or upload). `live_mbps` is the
/// instantaneous rate since the PREVIOUS sample (what a live ledger row shows
/// while the phase is in flight); `avg_mbps` is the rate across the WHOLE
/// window since the phase began (what settles as the final result once the
/// phase's bounded duration ends). Averaging over the full run, rather than
/// trusting the last tick, smooths over one unusually slow or fast sample.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Window {
    pub first: Option<Sample>,
    pub prev: Option<Sample>,
    pub live_mbps: f64,
    pub avg_mbps: f64,
}

pub fn init_window() -> Window {
    Window::default()
}

/// Folds one `(t, bytes)` reading (a millisecond timestamp paired with a
/// cumulative rx_bytes/tx_bytes counter) into the window.
pub fn add_sample(state: &Window, t: f64, bytes: f64) -> Window {
    let sample = Sample { t, bytes };
    let (Some(first), Some(prev)) = (state.first, state.prev) else {
        return Window { first: Some(sample), prev: Some(sample), live_mbps: 0.0, avg_mbps: 0.0 };
    };
    Window {
        first: Some(first),
        prev: Some(sample),
        live_mbps: mbps(bytes - prev.bytes, t - prev.t),
        avg_mbps: mbps(bytes - first.bytes, t - first.t),
    }
}

static DEV: LazyLock<Regex> = LazyLock::new(|| Regex::new(&format!(r"(?-u:\b)dev[{SPACE}]+([^{SPACE}]+)")).unwrap());

/// "192.0.2.1 via 10.0.2.2 dev eth0 src 10.0.2.15 uid 0" -> "eth0", scanning
/// every field for the literal "dev" token. `None` when `ip` printed nothing
/// (missing binary, no route at all) or the output has no "dev <iface>" pair.
pub fn parse_iface(route_output: &str) -> Option<String> {
    DEV.captures(route_output).map(|m| m[1].to_string())
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StatBytes {
    pub rx: f64,
    pub tx: f64,
}

/// `parseInt(text, 10)`: an optional sign and the leading digits, NaN when
/// there are none.
fn parse_int(text: &str) -> f64 {
    let t = js::trim(text);
    let (sign, digits) = match t.as_bytes().first() {
        Some(b'-') => (-1.0, &t[1..]),
        Some(b'+') => (1.0, &t[1..]),
        _ => (1.0, t),
    };
    let end = digits.bytes().position(|b| !b.is_ascii_digit()).unwrap_or(digits.len());
    if end == 0 {
        return f64::NAN;
    }
    sign * digits[..end].parse::<f64>().unwrap_or(f64::NAN)
}

/// Two-line `cat rx_bytes tx_bytes` stdout -> rx and tx. `None` on anything
/// short of two parseable non-negative integers: a missing or unreadable
/// statistics file leaves `cat`'s stdout short a line (it prints an error to
/// stderr for that argument and moves on to the next), and an interface that
/// disappears mid-read can leave the file empty.
pub fn parse_stat_bytes(text: &str) -> Option<StatBytes> {
    let lines: Vec<&str> = text.split('\n').map(js::trim).filter(|l| !l.is_empty()).collect();
    if lines.len() < 2 {
        return None;
    }
    let (rx, tx) = (parse_int(lines[0]), parse_int(lines[1]));
    if !rx.is_finite() || !tx.is_finite() || rx < 0.0 || tx < 0.0 {
        return None;
    }
    Some(StatBytes { rx, tx })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mbps_normal_rate() {
        // 1,000,000 bytes over 1000ms = 8 Mbps.
        assert_eq!(mbps(1000000.0, 1000.0), 8.0);
    }

    #[test]
    fn mbps_zero_duration_guard() {
        assert_eq!(mbps(1000000.0, 0.0), 0.0);
    }

    #[test]
    fn mbps_negative_duration_guard() {
        assert_eq!(mbps(1000000.0, -50.0), 0.0);
    }

    #[test]
    fn mbps_counter_reset_guard() {
        // bytes went backwards (interface flapped / counter wrapped).
        assert_eq!(mbps(-500.0, 1000.0), 0.0);
    }

    #[test]
    fn mbps_zero_delta() {
        assert_eq!(mbps(0.0, 1000.0), 0.0);
    }

    #[test]
    fn format_mbps_zero() {
        assert_eq!(format_mbps(0.0), "0.0");
    }

    #[test]
    fn format_mbps_negative_reads_as_zero() {
        assert_eq!(format_mbps(-3.0), "0.0");
    }

    #[test]
    fn format_mbps_under_ten_keeps_decimal() {
        assert_eq!(format_mbps(7.34), "7.3");
    }

    #[test]
    fn format_mbps_ten_and_above_rounds() {
        assert_eq!(format_mbps(10.0), "10");
        assert_eq!(format_mbps(123.6), "124");
    }

    #[test]
    fn format_mbps_ties_round_up_like_to_fixed() {
        assert_eq!(format_mbps(7.25), "7.3");
        assert_eq!(format_mbps(0.75), "0.8");
        assert_eq!(format_mbps(9.96), "10.0");
    }

    #[test]
    fn fill_fraction_zero() {
        assert_eq!(fill_fraction(0.0, Some(1000.0)), 0.0);
    }

    #[test]
    fn fill_fraction_mid_scale() {
        assert_eq!(fill_fraction(500.0, Some(1000.0)), 0.5);
    }

    #[test]
    fn fill_fraction_caps_at_one() {
        assert_eq!(fill_fraction(5000.0, Some(1000.0)), 1.0);
    }

    #[test]
    fn fill_fraction_default_max_when_omitted() {
        assert_eq!(fill_fraction(500.0, None), 0.5);
    }

    #[test]
    fn first_sample_seeds_zero_rates() {
        let w = add_sample(&init_window(), 1000.0, 5000.0);
        assert_eq!(w.live_mbps, 0.0);
        assert_eq!(w.avg_mbps, 0.0);
    }

    #[test]
    fn second_sample_computes_live_and_avg() {
        let mut w = init_window();
        w = add_sample(&w, 0.0, 0.0);
        // +1,000,000 bytes over 1000ms = 8 Mbps, live and avg agree on the
        // second sample (the window so far is just the one interval).
        w = add_sample(&w, 1000.0, 1000000.0);
        assert_eq!(w.live_mbps, 8.0);
        assert_eq!(w.avg_mbps, 8.0);
    }

    #[test]
    fn avg_covers_whole_window_not_just_last_tick() {
        let mut w = init_window();
        w = add_sample(&w, 0.0, 0.0);
        w = add_sample(&w, 1000.0, 1000000.0); // fast first second: 8 Mbps
        w = add_sample(&w, 2000.0, 1125000.0); // slow second second: 1 Mbps
        assert_eq!(w.live_mbps, 1.0);
        // whole window: 1,125,000 bytes over 2000ms = 4.5 Mbps.
        assert_eq!(w.avg_mbps, 4.5);
    }

    #[test]
    fn counter_reset_mid_window_reads_live_zero() {
        let mut w = init_window();
        w = add_sample(&w, 0.0, 5000000.0);
        w = add_sample(&w, 1000.0, 4000000.0); // counter went backwards
        assert_eq!(w.live_mbps, 0.0);
        assert_eq!(w.avg_mbps, 0.0);
    }

    #[test]
    fn zero_duration_between_samples_reads_zero() {
        let mut w = init_window();
        w = add_sample(&w, 1000.0, 0.0);
        w = add_sample(&w, 1000.0, 500000.0); // same timestamp twice
        assert_eq!(w.live_mbps, 0.0);
    }

    #[test]
    fn parse_iface_from_real_route_get_shape() {
        assert_eq!(parse_iface("1.1.1.1 via 10.0.2.2 dev eth0 src 10.0.2.15 uid 0 \n    cache").as_deref(), Some("eth0"));
    }

    #[test]
    fn parse_iface_missing_dev_token_is_none() {
        assert_eq!(parse_iface("RTNETLINK answers: Network is unreachable"), None);
    }

    #[test]
    fn parse_iface_empty_output_is_none() {
        assert_eq!(parse_iface(""), None);
    }

    #[test]
    fn parse_stat_bytes_normal_two_lines() {
        let s = parse_stat_bytes("123456\n789012\n").unwrap();
        assert_eq!(s.rx, 123456.0);
        assert_eq!(s.tx, 789012.0);
    }

    #[test]
    fn parse_stat_bytes_missing_line_is_none() {
        assert_eq!(parse_stat_bytes("123456\n"), None);
    }

    #[test]
    fn parse_stat_bytes_empty_is_none() {
        assert_eq!(parse_stat_bytes(""), None);
    }

    #[test]
    fn parse_stat_bytes_non_numeric_is_none() {
        assert_eq!(parse_stat_bytes("cat: No such file or directory\ncat: No such file or directory\n"), None);
    }
}
