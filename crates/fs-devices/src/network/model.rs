//! Pure model for the network panel's wifi rows: sort order, section
//! membership, security classification, and the signal-bar glyph. Ported from
//! `shell/Network/model.js`.
//!
//! Signal strength is the toolkit's native 0..1 fraction, not a percentage.

use std::cmp::Ordering;

use crate::js;

/// Quickshell's `WifiSecurityType` (src/network/enums.hpp:107-128), by its
/// integer value.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WifiSecurityType {
    Wpa3SuiteB192 = 0,
    Sae = 1,
    Wpa2Eap = 2,
    Wpa2Psk = 3,
    WpaEap = 4,
    WpaPsk = 5,
    StaticWep = 6,
    DynamicWep = 7,
    Leap = 8,
    Owe = 9,
    Open = 10,
    Unknown = 11,
}

impl TryFrom<i32> for WifiSecurityType {
    type Error = i32;

    fn try_from(n: i32) -> Result<Self, i32> {
        use WifiSecurityType::*;
        Ok(match n {
            0 => Wpa3SuiteB192,
            1 => Sae,
            2 => Wpa2Eap,
            3 => Wpa2Psk,
            4 => WpaEap,
            5 => WpaPsk,
            6 => StaticWep,
            7 => DynamicWep,
            8 => Leap,
            9 => Owe,
            10 => Open,
            11 => Unknown,
            _ => return Err(n),
        })
    }
}

/// Quickshell's `ConnectionFailReason` (src/network/enums.hpp:67-84).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionFailReason {
    Unknown = 0,
    NoSecrets = 1,
    WifiClientDisconnected = 2,
    WifiClientFailed = 3,
    WifiAuthTimeout = 4,
    WifiNetworkLost = 5,
}

impl TryFrom<i32> for ConnectionFailReason {
    type Error = i32;

    fn try_from(n: i32) -> Result<Self, i32> {
        use ConnectionFailReason::*;
        Ok(match n {
            0 => Unknown,
            1 => NoSecrets,
            2 => WifiClientDisconnected,
            3 => WifiClientFailed,
            4 => WifiAuthTimeout,
            5 => WifiNetworkLost,
            _ => return Err(n),
        })
    }
}

/// Open and Owe are the two unauthenticated types; everything else needs a
/// secret of some kind.
pub fn is_secured(security: WifiSecurityType) -> bool {
    !matches!(security, WifiSecurityType::Open | WifiSecurityType::Owe)
}

/// 802.1x/EAP networks need an identity and an nmcli side-script, not a plain
/// PSK, so the panel renders these as a dim ENTERPRISE tag instead of a prompt.
pub fn is_enterprise(security: WifiSecurityType) -> bool {
    matches!(security, WifiSecurityType::WpaEap | WifiSecurityType::Wpa2Eap)
}

/// What the sort and the section split read of a row; the panel's own row
/// type carries more.
pub trait WifiRowLike {
    fn connected(&self) -> bool;
    fn known(&self) -> bool;
    fn signal_strength(&self) -> f64;
}

#[derive(Clone, Debug, PartialEq)]
pub struct WifiRow {
    pub name: String,
    pub connected: bool,
    pub known: bool,
    pub signal_strength: f64,
}

impl WifiRowLike for WifiRow {
    fn connected(&self) -> bool {
        self.connected
    }

    fn known(&self) -> bool {
        self.known
    }

    fn signal_strength(&self) -> f64 {
        self.signal_strength
    }
}

/// `x || 0`: NaN reads as 0.
fn or_zero(x: f64) -> f64 {
    if x.is_nan() { 0.0 } else { x }
}

/// Connected first, then known (saved) networks, then everything else, each
/// tier sorted by signal strength descending. Non-mutating.
pub fn sort_wifi_rows<T: WifiRowLike + Clone>(rows: &[T]) -> Vec<T> {
    let mut list = rows.to_vec();
    list.sort_by(|a, b| {
        if a.connected() != b.connected() {
            return if a.connected() { Ordering::Less } else { Ordering::Greater };
        }
        if a.known() != b.known() {
            return if a.known() { Ordering::Less } else { Ordering::Greater };
        }
        or_zero(b.signal_strength()).partial_cmp(&or_zero(a.signal_strength())).unwrap_or(Ordering::Equal)
    });
    list
}

/// Section header a row falls under once [`sort_wifi_rows`] has grouped
/// connected in with known: the connected row is always known (you cannot be
/// connected to a network with no saved settings), so this only ever needs to
/// look at `known` itself.
pub fn section_of(row: &impl WifiRowLike) -> &'static str {
    if row.known() { "KNOWN" } else { "AVAILABLE" }
}

/// Status line for a `connectionFailed(reason)` signal.
pub fn failure_text(reason: ConnectionFailReason) -> &'static str {
    match reason {
        ConnectionFailReason::NoSecrets => "Passphrase required",
        ConnectionFailReason::WifiAuthTimeout => "Wrong password",
        ConnectionFailReason::WifiNetworkLost => "Network lost",
        _ => "Connection failed",
    }
}

/// A failure whose fix is typing the secret again rather than retrying.
pub fn is_secret_failure(reason: ConnectionFailReason) -> bool {
    matches!(reason, ConnectionFailReason::NoSecrets | ConnectionFailReason::WifiAuthTimeout)
}

/// Five-cell block/light-shade bar for a 0..1 fraction.
pub fn signal_bar(strength: f64) -> String {
    const SEGMENTS: usize = 5;
    let filled = if strength.is_nan() { 0.0 } else { js::round(strength.clamp(0.0, 1.0) * SEGMENTS as f64) };
    (0..SEGMENTS).map(|i| if (i as f64) < filled { '\u{2588}' } else { '\u{2591}' }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(name: &str, connected: bool, known: bool, signal_strength: f64) -> WifiRow {
        WifiRow { name: name.into(), connected, known, signal_strength }
    }

    fn names(rows: &[WifiRow]) -> String {
        rows.iter().map(|r| r.name.as_str()).collect::<Vec<_>>().join(",")
    }

    #[test]
    fn sort_wifi_rows_connected_then_known_then_signal_desc() {
        let sorted = sort_wifi_rows(&[
            row("A", false, true, 0.5),
            row("B", true, true, 0.2),
            row("C", false, false, 0.9),
            row("D", false, true, 0.8),
        ]);
        assert_eq!(names(&sorted), "B,D,A,C");
    }

    #[test]
    fn sort_wifi_rows_does_not_mutate_input() {
        let input = [row("A", false, true, 0.1), row("B", true, true, 0.9)];
        let before = input.clone();
        sort_wifi_rows(&input);
        assert_eq!(input, before);
    }

    #[test]
    fn section_of_known_vs_available() {
        assert_eq!(section_of(&row("A", false, true, 0.5)), "KNOWN");
        assert_eq!(section_of(&row("A", false, false, 0.5)), "AVAILABLE");
    }

    #[test]
    fn failure_text_mappings() {
        use ConnectionFailReason::*;
        assert_eq!(failure_text(NoSecrets), "Passphrase required");
        assert_eq!(failure_text(WifiAuthTimeout), "Wrong password");
        assert_eq!(failure_text(WifiNetworkLost), "Network lost");
        assert_eq!(failure_text(WifiClientFailed), "Connection failed");
        assert_eq!(failure_text(Unknown), "Connection failed");
        assert!(is_secret_failure(NoSecrets));
        assert!(is_secret_failure(WifiAuthTimeout));
        assert!(!is_secret_failure(WifiNetworkLost));
    }

    #[test]
    fn is_secured_open_and_owe_are_unsecured() {
        use WifiSecurityType::*;
        assert!(!is_secured(Open));
        assert!(!is_secured(Owe));
        assert!(is_secured(Wpa2Psk));
        assert!(is_secured(Sae));
    }

    #[test]
    fn is_enterprise_only_eap_types() {
        use WifiSecurityType::*;
        assert!(is_enterprise(WpaEap));
        assert!(is_enterprise(Wpa2Eap));
        assert!(!is_enterprise(Wpa2Psk));
        assert!(!is_enterprise(Open));
    }

    #[test]
    fn enum_values_mirror_the_toolkit_integers() {
        assert_eq!(WifiSecurityType::try_from(10), Ok(WifiSecurityType::Open));
        assert_eq!(WifiSecurityType::try_from(12), Err(12));
        assert_eq!(WifiSecurityType::Wpa2Psk as i32, 3);
        assert_eq!(ConnectionFailReason::try_from(4), Ok(ConnectionFailReason::WifiAuthTimeout));
        assert_eq!(ConnectionFailReason::try_from(6), Err(6));
    }

    #[test]
    fn signal_bar_full_and_empty() {
        assert_eq!(signal_bar(0.0), "░░░░░");
        assert_eq!(signal_bar(1.0), "█████");
    }

    #[test]
    fn signal_bar_rounds_to_nearest_segment() {
        assert_eq!(signal_bar(0.5), "███░░");
        assert_eq!(signal_bar(0.2), "█░░░░");
    }

    #[test]
    fn signal_bar_clamps_out_of_range() {
        assert_eq!(signal_bar(-1.0), "░░░░░");
        assert_eq!(signal_bar(2.0), "█████");
    }
}
