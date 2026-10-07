//! The Bluetooth audio devices the headset connect card watches: BlueZ's
//! devices whose icon says audio, or the smoke rig's list in their place.
//!
//! `FORMALSHELL_SMOKE_BLUETOOTH` is a JSON array of `{ address, name,
//! connected }` (see `fs_devices::earbuds::bluetooth_devices`); entries here
//! may add `icon` (a BlueZ icon name, `audio-headset` when absent) and
//! `battery` (0 to 100). A value starting with `@` names a file holding
//! that array, read again whenever it changes, which is how a leg connects
//! and disconnects a device on a rig with no controller.

use serde_json::Value;

#[derive(Clone, Debug, PartialEq)]
pub struct Headset {
    /// Upper case, as BlueZ hands it out.
    pub address: String,
    pub name: String,
    /// BlueZ's `Icon`: `audio-headset`, `audio-headphones`, `audio-speakers`.
    pub icon: String,
    pub connected: bool,
    /// BlueZ's Battery1, as a 0..1 fraction; none when nothing reports one.
    pub battery: Option<f64>,
}

/// The override's text: the variable's own value, or the file it names.
pub fn smoke_text() -> Option<String> {
    let value = std::env::var(fs_bluez::SMOKE_ENV).ok()?;
    match value.strip_prefix('@') {
        Some(path) => Some(std::fs::read_to_string(path).unwrap_or_default()),
        None => Some(value),
    }
}

/// The path an `@` value names.
pub fn smoke_file() -> Option<std::path::PathBuf> {
    let value = std::env::var(fs_bluez::SMOKE_ENV).ok()?;
    value.strip_prefix('@').map(std::path::PathBuf::from)
}

fn parse(text: &str) -> Option<Vec<Headset>> {
    let Value::Array(raw) = serde_json::from_str::<Value>(text).ok()? else { return None };
    Some(
        raw.iter()
            .filter_map(|d| {
                let address = d.get("address")?.as_str()?.to_uppercase();
                let name = d.get("name").and_then(Value::as_str).unwrap_or("").to_owned();
                Some(Headset {
                    address,
                    name,
                    icon: d.get("icon").and_then(Value::as_str).unwrap_or("audio-headset").to_owned(),
                    connected: d.get("connected") == Some(&Value::Bool(true)),
                    battery: d.get("battery").and_then(Value::as_f64).map(|p| (p / 100.0).clamp(0.0, 1.0)),
                })
            })
            .collect(),
    )
}

pub fn read(state: Option<&fs_bluez::state::State>, over: Option<&str>) -> Vec<Headset> {
    if let Some(list) = over.filter(|t| !t.is_empty()).and_then(parse) {
        return list;
    }
    let Some(state) = state else { return Vec::new() };
    let Some(adapter) = state.default_adapter() else { return Vec::new() };
    state
        .devices_of(&adapter.path)
        .into_iter()
        .filter(|d| d.icon.starts_with("audio-"))
        .map(|d| Headset {
            address: d.info.address.to_uppercase(),
            name: if d.info.name.is_empty() { d.info.device_name.clone() } else { d.info.name.clone() },
            icon: d.icon.clone(),
            connected: d.info.connected,
            battery: d.info.battery_available.then_some(d.info.battery),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_override_replaces_the_adapter_with_headsets() {
        let list = read(None, Some(r#"[{"address":"ac:12:2f:11:22:33","name":"Liberty 4 NC","connected":true,"battery":80}]"#));
        assert_eq!(
            list,
            vec![Headset {
                address: "AC:12:2F:11:22:33".into(),
                name: "Liberty 4 NC".into(),
                icon: "audio-headset".into(),
                connected: true,
                battery: Some(0.8),
            }]
        );
    }

    #[test]
    fn nothing_without_an_override_or_an_adapter() {
        assert!(read(None, None).is_empty());
        assert!(read(None, Some("")).is_empty());
        assert!(read(None, Some("not json")).is_empty());
    }
}
