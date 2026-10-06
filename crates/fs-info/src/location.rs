//! Location's own lookups for a machine geoclue cannot place. geoclue's wifi
//! source only reads wpa_supplicant, so under iwd (NetworkManager's
//! wifi.backend = "iwd") it never has a BSSID to send and never gets a fix.
//! LocationService then sends beaconDB the same query itself, with the BSSIDs
//! iwd publishes on the system bus (or nmcli's, under wpa_supplicant), and
//! beaconDB answers from its IP database when it knows none of them.

use std::sync::LazyLock;

use regex::Regex;
use serde::Serialize;
use serde_json::Value;

use crate::js;

pub const GEOLOCATE_URL: &str = "https://api.beacondb.net/v1/geolocate";

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessPoint {
    pub mac_address: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signal_strength: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency: Option<i64>,
}

impl AccessPoint {
    fn bare(mac: String) -> AccessPoint {
        AccessPoint { mac_address: mac, signal_strength: None, frequency: None }
    }
}

fn is_nomap(name: &str) -> bool {
    name.ends_with("_nomap")
}

/// `busctl --json=short call net.connman.iwd / ...ObjectManager
/// GetManagedObjects`: every BasicServiceSet's Address, minus the ones under
/// a network whose name opts out of location services (`_nomap`).
pub fn access_points_from_iwd(text: &str) -> Vec<AccessPoint> {
    let Ok(parsed) = serde_json::from_str::<Value>(text) else {
        return Vec::new();
    };
    let Some(objects) = parsed.get("data").and_then(|d| d.get(0)).and_then(Value::as_object)
    else {
        return Vec::new();
    };
    let mut result = Vec::new();
    for (path, object) in objects {
        let Some(bss) = object.get("net.connman.iwd.BasicServiceSet") else {
            continue;
        };
        if !js::truthy(bss.get("Address")) {
            continue;
        }
        let parent = path.rfind('/').and_then(|i| objects.get(&path[..i]));
        let name = parent
            .and_then(|p| p.get("net.connman.iwd.Network"))
            .and_then(|n| n.get("Name"))
            .filter(|n| js::truthy(Some(n)))
            .map(|n| js::str_of(n.get("data")))
            .unwrap_or_default();
        if is_nomap(&name) {
            continue;
        }
        let address = js::str_of(bss.get("Address").and_then(|a| a.get("data")));
        result.push(AccessPoint::bare(address.to_lowercase()));
    }
    result
}

/// Terse mode escapes the colons inside a field with a backslash.
fn terse_fields(line: &str) -> Vec<String> {
    let mut fields = vec![String::new()];
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => match chars.next() {
                Some(next) => fields.last_mut().unwrap().push(next),
                None => fields.last_mut().unwrap().push('\\'),
            },
            ':' => fields.push(String::new()),
            c => fields.last_mut().unwrap().push(c),
        }
    }
    fields
}

/// `nmcli -t -f BSSID,SSID,SIGNAL,FREQ dev wifi list`.
pub fn access_points_from_nmcli(text: &str) -> Vec<AccessPoint> {
    static BSSID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[0-9A-Fa-f:]{17}$").unwrap());
    let mut result = Vec::new();
    for line in text.split('\n') {
        let fields = terse_fields(line);
        if fields.len() < 4 || !BSSID.is_match(&fields[0]) || is_nomap(&fields[1]) {
            continue;
        }
        result.push(AccessPoint {
            mac_address: fields[0].to_lowercase(),
            signal_strength: js::parse_int(&fields[2]).map(|s| js::round(s / 2.0 - 100.0) as i64),
            frequency: js::parse_int(&fields[3]).map(|f| f as i64),
        });
    }
    result
}

/// The scan script prints which backend answered on its first line.
pub fn access_points_from_scan(text: &str) -> Vec<AccessPoint> {
    let (head, rest) = text.split_once('\n').unwrap_or((text, ""));
    match head {
        "iwd" => access_points_from_iwd(rest),
        "nm" => access_points_from_nmcli(rest),
        _ => Vec::new(),
    }
}

pub fn geolocate_body(access_points: &[AccessPoint]) -> String {
    serde_json::json!({ "considerIp": true, "wifiAccessPoints": access_points }).to_string()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
    Wifi,
    Ip,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Wifi => "wifi",
            Source::Ip => "ip",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Fix {
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy: f64,
    pub source: Source,
}

/// beaconDB marks its IP answer `fallback: "ipf"`; anything without a usable
/// location is `None`.
pub fn parse_geolocate(body: &str) -> Option<Fix> {
    let data: Value = serde_json::from_str(body).ok()?;
    let loc = data.get("location").filter(|l| js::truthy(Some(l)))?;
    let latitude = js::number(loc.get("lat"));
    let longitude = js::number(loc.get("lng"));
    if !latitude.is_finite() || !longitude.is_finite() {
        return None;
    }
    let accuracy = js::number(data.get("accuracy"));
    Some(Fix {
        latitude,
        longitude,
        accuracy: if accuracy.is_nan() { 0.0 } else { accuracy },
        source: if data.get("fallback").and_then(Value::as_str) == Some("ipf") {
            Source::Ip
        } else {
            Source::Wifi
        },
    })
}

/// Rounded to about a kilometre, so a fix that drifts a few metres is the
/// same place and never another lookup.
pub fn place_key(latitude: f64, longitude: f64) -> String {
    if !latitude.is_finite() || !longitude.is_finite() {
        return String::new();
    }
    format!("{},{}", js::to_fixed2(latitude), js::to_fixed2(longitude))
}

pub fn reverse_url(key: &str) -> String {
    let mut parts = key.split(',');
    let lat = parts.next().unwrap_or("");
    // A key without a comma reads its longitude as "undefined", the way the
    // string concatenation always has.
    let lon = parts.next().unwrap_or("undefined");
    format!(
        "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=en&lat={lat}&lon={lon}"
    )
}

/// "Teguise, Canary Islands": the town and its region, "" when Nominatim has
/// neither.
pub fn parse_place(body: &str) -> String {
    let Ok(data) = serde_json::from_str::<Value>(body) else {
        return String::new();
    };
    let Some(data) = data.as_object() else {
        return String::new();
    };
    let address = data.get("address").filter(|a| js::truthy(Some(a)));
    let first_of = |keys: &[&str], fallback: Option<&Value>| -> String {
        let hit = keys
            .iter()
            .filter_map(|k| address.and_then(|a| a.get(*k)))
            .chain(fallback)
            .find(|v| js::truthy(Some(v)));
        js::str_of(hit)
    };
    let town = first_of(&["city", "town", "village", "municipality", "county"], data.get("name"));
    let region = first_of(&["state", "country"], None);
    if !town.is_empty() && !region.is_empty() && town != region {
        format!("{town}, {region}")
    } else if !town.is_empty() {
        town
    } else {
        region
    }
}
