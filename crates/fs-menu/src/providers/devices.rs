//! The device routes: Wi-Fi, Bluetooth, audio and radio. Each takes the live
//! source's state as plain data, so the ordering, the ticks and the per-row
//! status text are testable without a radio.

use std::collections::HashSet;
use std::sync::LazyLock;

use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, utf8_percent_encode};
use regex::Regex;

use crate::node::{Kind, Node};

/// `encodeURIComponent`'s unreserved set.
const URI_COMPONENT: &AsciiSet = &NON_ALPHANUMERIC.remove(b'-').remove(b'_').remove(b'.').remove(b'!').remove(b'~').remove(b'*').remove(b'\'').remove(b'(').remove(b')');

/// Row ids are dotted tree paths, so a key that can carry a dot (an SSID, a
/// PipeWire node name) is escaped before it goes into one.
pub fn id_part(s: &str) -> String {
    utf8_percent_encode(s, URI_COMPONENT).to_string().replace('.', "%2E")
}

fn key_row(id: String, label: String, action: &str, verb: &str) -> Node {
    Node {
        action: Some(action.to_string()),
        verb: Some(verb.to_string()),
        keep_open: Some(true),
        ..Node::new(id, label, Kind::Action)
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct WifiNetwork {
    pub name: String,
    pub known: bool,
    pub connected: bool,
    pub secured: bool,
    pub enterprise: bool,
    pub signal: f64,
    /// Overrides `signal` when the source carries its own 0..1 fraction.
    pub signal_strength: Option<f64>,
}

/// `LiveMenuSources.wifi`: the device and radio flags, the scanned networks,
/// and the Wi-Fi service's action in flight and last failure.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct WifiState {
    pub has_device: bool,
    pub enabled: bool,
    pub networks: Vec<WifiNetwork>,
    pub action_ssid: String,
    pub action_kind: String,
    pub failure_ssid: String,
    pub failure_text: String,
}

/// Connected first, then known (saved) networks, then everything else, each
/// tier by signal strength descending.
fn sort_wifi_rows(rows: &mut [(WifiNetwork, f64)]) {
    rows.sort_by(|(a, sa), (b, sb)| {
        b.connected
            .cmp(&a.connected)
            .then(b.known.cmp(&a.known))
            .then(sb.partial_cmp(sa).unwrap_or(std::cmp::Ordering::Equal))
    });
}

/// Wi-Fi route. Saved networks are reachable from a root query; nearby ones
/// are `local_only`, so a stranger's SSID never turns up in a search typed
/// outside the level. Enter on a secured unknown network asks for a password,
/// Shift+Enter on a saved one forgets it.
pub fn wifi_rows(st: &WifiState) -> Vec<Node> {
    if !st.has_device {
        return vec![Node::note("wifi.unavailable", "No Wi-Fi device")];
    }
    if !st.enabled {
        return vec![key_row("wifi.off".into(), "Turn Wi-Fi on".into(), "@ipc:wifi.enable", "Turn on")];
    }
    let mut seen: HashSet<&str> = HashSet::new();
    let mut visible: Vec<(WifiNetwork, f64)> = st
        .networks
        .iter()
        .filter(|n| !n.name.is_empty() && seen.insert(n.name.as_str()))
        .map(|n| (n.clone(), n.signal_strength.unwrap_or(n.signal)))
        .collect();
    if visible.is_empty() {
        return vec![Node::note("wifi.empty", "No networks found")];
    }
    sort_wifi_rows(&mut visible);
    visible
        .into_iter()
        .map(|(n, _)| {
            let busy = match st.action_kind.as_str() {
                "connect" => "Connecting",
                "disconnect" => "Disconnecting",
                "forget" => "Forgetting",
                _ => "",
            };
            let desc = if !st.action_kind.is_empty() && st.action_ssid == n.name {
                busy
            } else if st.failure_ssid == n.name && !st.failure_text.is_empty() {
                st.failure_text.as_str()
            } else if !n.known {
                if n.enterprise {
                    "Enterprise"
                } else if n.secured {
                    "Secured"
                } else {
                    ""
                }
            } else {
                ""
            };
            let mut row = Node {
                desc: Some(desc.to_string()),
                verb: Some(if n.connected { "Disconnect" } else { "Connect" }.to_string()),
                action: Some(format!("@ipc:wifi.activate:{}", n.name)),
                checked: Some(format!("@state:wifi.ssid={}", n.name)),
                keep_open: Some(true),
                local_only: !n.known,
                section: Some(if n.known { "Saved" } else { "Nearby" }.to_string()),
                ..Node::new(format!("wifi.net.{}", id_part(&n.name)), n.name.clone(), Kind::Action)
            };
            if n.known {
                row.alternate = Some(format!("@ipc:wifi.forget:{}", n.name));
                row.alternate_label = Some("Forget".to_string());
            }
            row
        })
        .collect()
}

/// A paired or connected device. `activity` and `battery` are the display
/// strings the Bluetooth model already formed.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct BluetoothDevice {
    pub address: String,
    pub name: String,
    pub device_name: String,
    pub connected: bool,
    pub paired: bool,
    pub bonded: bool,
    pub trusted: bool,
    pub activity: String,
    pub battery: String,
}

/// `LiveMenuSources.bluetooth`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct BluetoothState {
    pub available: bool,
    pub enabled: bool,
    pub devices: Vec<BluetoothDevice>,
}

static MAC_SHAPED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new("(?i)^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$").expect("static regex"));
static UUID_SHAPED: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new("(?i)^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32})$")
        .expect("static regex")
});

/// Rejects the empty string and the two label shapes BlueZ falls back to when
/// a device has not advertised a real name yet, a raw address or a service
/// UUID, neither of which is worth showing a person.
fn has_human_name(name: &str) -> bool {
    let label = crate::jsstr::trim(name);
    !label.is_empty() && !MAC_SHAPED.is_match(label) && !UUID_SHAPED.is_match(label)
}

fn device_label(d: &BluetoothDevice) -> &str {
    if !d.name.is_empty() { &d.name } else { &d.device_name }
}

/// The panel model's connected and known buckets (a device with no human
/// name is dropped from both), each sorted by label. Sorting here is a
/// case-insensitive comparison, an approximation of `String.localeCompare`.
fn paired_devices(devices: &[BluetoothDevice]) -> Vec<&BluetoothDevice> {
    fn sorted(mut list: Vec<&BluetoothDevice>) -> Vec<&BluetoothDevice> {
        list.sort_by_cached_key(|d| (device_label(d).to_lowercase(), device_label(d).to_string()));
        list
    }
    let named = devices.iter().filter(|d| has_human_name(device_label(d)));
    let connected = sorted(named.clone().filter(|d| d.connected).collect());
    let known = sorted(named.filter(|d| !d.connected && (d.paired || d.bonded || d.trusted)).collect());
    connected.into_iter().chain(known).collect()
}

/// Bluetooth route. Paired devices only: pairing is watching a scan fill in,
/// which stays the panel's job. Rows are reachable from a root query.
pub fn bluetooth_rows(st: &BluetoothState) -> Vec<Node> {
    if !st.available {
        return vec![Node::note("bluetooth.unavailable", "No Bluetooth adapter")];
    }
    if !st.enabled {
        return vec![key_row("bluetooth.off".into(), "Turn Bluetooth on".into(), "@ipc:bluetooth.power:on", "Turn on")];
    }
    let devices = paired_devices(&st.devices);
    if devices.is_empty() {
        return vec![Node::note("bluetooth.empty", "No paired devices")];
    }
    devices
        .into_iter()
        .map(|d| Node {
            desc: Some(if !d.activity.is_empty() { d.activity.clone() } else { d.battery.clone() }),
            verb: Some(if d.connected { "Disconnect" } else { "Connect" }.to_string()),
            action: Some(format!("@ipc:bluetooth.toggle:{}", d.address)),
            checked: Some(format!("@state:bluetooth.connected={}", d.address.to_uppercase())),
            keep_open: Some(true),
            ..Node::new(format!("bluetooth.dev.{}", id_part(&d.address)), device_label(d), Kind::Action)
        })
        .collect()
}

/// One entry of the audio model's device rows.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AudioDevice {
    pub name: String,
    pub label: String,
    pub is_sink: bool,
}

/// Audio route.
pub fn audio_rows(devices: &[AudioDevice]) -> Vec<Node> {
    if devices.is_empty() {
        return vec![Node::note("audio.unavailable", "No audio devices")];
    }
    devices
        .iter()
        .map(|d| {
            let verb = if d.is_sink { "sink" } else { "source" };
            Node {
                section: Some(if d.is_sink { "Output" } else { "Input" }.to_string()),
                action: Some(format!("@ipc:audio.{verb}:{}", d.name)),
                verb: Some("Use".to_string()),
                checked: Some(format!("@state:audio.{verb}={}", d.name)),
                keep_open: Some(true),
                ..Node::new(
                    format!("audio.{}{}", if d.is_sink { "output." } else { "input." }, id_part(&d.name)),
                    d.label.clone(),
                    Kind::Action,
                )
            }
        })
        .collect()
}

/// `":r"` root trigger: the station query after it ("" for the bare `":r"`),
/// or `None` when `text` is not the trigger.
pub fn radio_trigger_query(text: &str) -> Option<&str> {
    if text == ":r" {
        return Some("");
    }
    text.strip_prefix(":r ")
}

fn radio_tick(uuid: &str) -> String {
    format!("@state:radio.station={uuid}")
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RadioStation {
    pub uuid: String,
    pub name: String,
    pub country: String,
    pub codec: String,
}

/// `LiveMenuSources.radio`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RadioState {
    pub running: bool,
    pub favorites: Vec<RadioStation>,
}

/// Radio route. Favourites are reachable from a root query; station search
/// results come from `radio_result_rows` and are `local_only`.
pub fn radio_rows(st: &RadioState) -> Vec<Node> {
    let mut rows = Vec::new();
    if st.running {
        rows.push(key_row("radio.stop".into(), "Stop".into(), "@ipc:radio.stop", "Stop"));
    }
    for s in &st.favorites {
        rows.push(Node {
            desc: Some(s.country.clone()),
            action: Some(format!("@ipc:radio.fav:{}", s.uuid)),
            verb: Some("Play".to_string()),
            checked: Some(radio_tick(&s.uuid)),
            keep_open: Some(true),
            alternate: Some(format!("@ipc:radio.unfavorite:{}", s.uuid)),
            alternate_label: Some("Remove favorite".to_string()),
            ..Node::new(format!("radio.fav.{}", id_part(&s.uuid)), s.name.clone(), Kind::Action)
        });
    }
    rows
}

/// Enter closes the launcher on a result: a stream starting is the answer, and
/// the list is a one-off search rather than a set to flip through.
pub fn radio_result_rows(results: &[RadioStation], favorite_set: &HashSet<String>) -> Vec<Node> {
    results
        .iter()
        .map(|s| {
            let fav = favorite_set.contains(&s.uuid);
            let desc = [s.country.as_str(), s.codec.as_str()].into_iter().filter(|x| !x.is_empty()).collect::<Vec<_>>().join(" ");
            Node {
                desc: Some(desc),
                action: Some(format!("@ipc:radio.play:{}", s.uuid)),
                verb: Some("Play".to_string()),
                checked: Some(radio_tick(&s.uuid)),
                local_only: true,
                alternate: Some(format!("@ipc:radio.{}:{}", if fav { "unfavorite" } else { "favorite" }, s.uuid)),
                alternate_label: Some(if fav { "Remove favorite" } else { "Add favorite" }.to_string()),
                ..Node::new(format!("radio.result.{}", id_part(&s.uuid)), s.name.clone(), Kind::Action)
            }
        })
        .collect()
}

pub fn radio_searching_row() -> Node {
    Node::note("radio.searching", "Searching")
}

pub fn radio_no_results_row() -> Node {
    Node::note("radio.noresults", "No results")
}

pub fn radio_failed_row() -> Node {
    Node::note("radio.failed", "Search failed")
}
