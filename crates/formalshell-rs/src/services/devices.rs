//! What the bar's device cells read: the default Bluetooth adapter
//! (fs-bluez), NetworkManager's devices, and the default sink's volume.
//! Each answers its own honest unavailable state when the daemon behind it
//! is not on the bus.

use std::time::Duration;

use async_io::Timer;
use futures_lite::StreamExt;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Bluetooth {
    /// None with no adapter (or no bluetoothd).
    pub powered: Option<bool>,
    pub connected: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Network {
    /// False until NetworkManager has answered.
    pub known: bool,
    pub wired: bool,
    pub wifi: bool,
    pub wifi_enabled: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Audio {
    /// None until a sink has answered.
    pub volume: Option<f64>,
    pub muted: bool,
    /// The default sink's description, or its node name.
    pub name: String,
}

#[derive(Default)]
pub struct State {
    pub bluetooth: Bluetooth,
    pub network: Network,
    pub audio: Audio,
}

pub enum Diff {
    Bluetooth(Bluetooth),
    Network(Network),
    Audio(Audio),
}

impl State {
    pub fn apply(&mut self, diff: Diff) -> bool {
        fn set<T: PartialEq>(slot: &mut T, v: T) -> bool {
            let changed = *slot != v;
            *slot = v;
            changed
        }
        match diff {
            Diff::Bluetooth(v) => set(&mut self.bluetooth, v),
            Diff::Network(v) => set(&mut self.network, v),
            Diff::Audio(v) => set(&mut self.audio, v),
        }
    }
}

pub fn start(ctx: &Ctx) {
    ctx.spawn(bluetooth(ctx.clone()));
    ctx.spawn(network(ctx.clone()));
    ctx.spawn(audio(ctx.clone()));
}

fn bt_snapshot(state: &fs_bluez::state::State) -> Bluetooth {
    let Some(adapter) = state.default_adapter() else { return Bluetooth::default() };
    let connected = state
        .devices_of(&adapter.path)
        .into_iter()
        .filter(|d| d.info.connected)
        .map(|d| if d.info.name.is_empty() { d.info.device_name } else { d.info.name })
        .collect();
    Bluetooth { powered: Some(adapter.powered), connected }
}

async fn bluetooth(ctx: Ctx) {
    let Ok(conn) = zbus::Connection::system().await else {
        return ctx.publish(store::Diff::Devices(Diff::Bluetooth(Bluetooth::default())));
    };
    let (bluez, events, monitor) = match fs_bluez::Bluez::connect(&conn).await {
        Ok(v) => v,
        Err(err) => {
            eprintln!("bluetooth: {err}");
            return ctx.publish(store::Diff::Devices(Diff::Bluetooth(Bluetooth::default())));
        }
    };
    ctx.spawn(monitor.run());
    ctx.publish(store::Diff::Devices(Diff::Bluetooth(bt_snapshot(&bluez.state()))));
    while events.recv().await.is_ok() {
        ctx.publish(store::Diff::Devices(Diff::Bluetooth(bt_snapshot(&bluez.state()))));
    }
}

const NM: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
/// NMDeviceType and NMDeviceState's numbers.
const TYPE_ETHERNET: u32 = 1;
const TYPE_WIFI: u32 = 2;
const STATE_ACTIVATED: u32 = 100;

async fn nm_prop<T: TryFrom<OwnedValue>>(conn: &zbus::Connection, path: &str, iface: &str, name: &str) -> Option<T> {
    let proxy = zbus::fdo::PropertiesProxy::builder(conn).destination(NM).ok()?.path(path).ok()?.build().await.ok()?;
    let iface = zbus::names::InterfaceName::try_from(iface).ok()?;
    proxy.get(iface, name).await.ok().and_then(|v| T::try_from(v).ok())
}

async fn nm_snapshot(conn: &zbus::Connection) -> Network {
    let Some(devices) = nm_prop::<Vec<OwnedObjectPath>>(conn, NM_PATH, NM, "Devices").await else {
        return Network::default();
    };
    let mut out = Network { known: true, ..Network::default() };
    out.wifi_enabled = nm_prop::<bool>(conn, NM_PATH, NM, "WirelessEnabled").await.unwrap_or(false);
    for path in devices {
        let iface = "org.freedesktop.NetworkManager.Device";
        let kind = nm_prop::<u32>(conn, path.as_str(), iface, "DeviceType").await.unwrap_or(0);
        let state = nm_prop::<u32>(conn, path.as_str(), iface, "State").await.unwrap_or(0);
        let up = state == STATE_ACTIVATED;
        match kind {
            TYPE_ETHERNET => out.wired |= up,
            TYPE_WIFI => out.wifi |= up,
            _ => {}
        }
    }
    out
}

/// Re-read on every NetworkManager signal: device state changes arrive as
/// `StateChanged` on the device objects and as property changes on the root.
async fn network(ctx: Ctx) {
    let Ok(conn) = zbus::Connection::system().await else {
        return ctx.publish(store::Diff::Devices(Diff::Network(Network::default())));
    };
    let rule = zbus::MatchRule::builder().msg_type(zbus::message::Type::Signal).sender(NM).map(|b| b.build());
    let mut signals = match rule {
        Ok(rule) => zbus::MessageStream::for_match_rule(rule, &conn, None).await.ok(),
        Err(_) => None,
    };
    ctx.publish(store::Diff::Devices(Diff::Network(nm_snapshot(&conn).await)));
    let Some(signals) = signals.as_mut() else { return };
    while signals.next().await.is_some() {
        // A burst of signals per change; one read after it settles.
        Timer::after(Duration::from_millis(100)).await;
        ctx.publish(store::Diff::Devices(Diff::Network(nm_snapshot(&conn).await)));
    }
}

/// `wpctl get-volume` prints `Volume: 0.40` and ` [MUTED]` when muted.
fn parse_wpctl(out: &str) -> Option<Audio> {
    let rest = out.trim().strip_prefix("Volume:")?.trim();
    let volume = rest.split_whitespace().next()?.parse::<f64>().ok()?;
    Some(Audio { volume: Some(volume), muted: rest.contains("[MUTED]"), name: String::new() })
}

/// `wpctl inspect`'s `node.description`, else `node.name`.
fn parse_inspect(out: &str) -> String {
    let prop = |key: &str| {
        out.lines().find_map(|l| {
            let l = l.trim_start_matches(['*', ' ']);
            let rest = l.strip_prefix(key)?.trim_start().strip_prefix('=')?;
            Some(rest.trim().trim_matches('"').to_owned())
        })
    };
    prop("node.description").or_else(|| prop("node.name")).unwrap_or_default()
}

async fn read_volume() -> Audio {
    let out = async_process::Command::new("wpctl").args(["get-volume", "@DEFAULT_AUDIO_SINK@"]).output().await;
    let mut audio = out.ok().and_then(|o| parse_wpctl(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default();
    if audio.volume.is_some() {
        let out = async_process::Command::new("wpctl").args(["inspect", "@DEFAULT_AUDIO_SINK@"]).output().await;
        audio.name = out.map(|o| parse_inspect(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default();
    }
    audio
}

/// NetworkManager's radio switch.
pub fn set_wifi(ctx: &Ctx, on: bool) {
    let ctx2 = ctx.clone();
    ctx.spawn(async move {
        if let Ok(conn) = zbus::Connection::system().await
            && let Ok(proxy) = zbus::Proxy::new(&conn, NM, NM_PATH, NM).await
        {
            let _ = proxy.set_property("WirelessEnabled", on).await;
            ctx2.publish(store::Diff::Devices(Diff::Network(nm_snapshot(&conn).await)));
        }
    });
}

/// `RequestScan` on every Wi-Fi device NetworkManager has.
pub fn rescan(ctx: &Ctx) {
    ctx.spawn(async move {
        let Ok(conn) = zbus::Connection::system().await else { return };
        let Some(devices) = nm_prop::<Vec<OwnedObjectPath>>(&conn, NM_PATH, NM, "Devices").await else { return };
        for path in devices {
            let iface = "org.freedesktop.NetworkManager.Device";
            if nm_prop::<u32>(&conn, path.as_str(), iface, "DeviceType").await != Some(TYPE_WIFI) {
                continue;
            }
            let wireless = "org.freedesktop.NetworkManager.Device.Wireless";
            if let Ok(proxy) = zbus::Proxy::new(&conn, NM, path.as_str(), wireless).await {
                let options: std::collections::HashMap<&str, zbus::zvariant::Value> = Default::default();
                let _: zbus::Result<()> = proxy.call("RequestScan", &(options,)).await;
            }
        }
    });
}

/// Polled until the PipeWire client lands with the audio panel.
async fn audio(ctx: Ctx) {
    loop {
        ctx.publish(store::Diff::Devices(Diff::Audio(read_volume().await)));
        Timer::after(Duration::from_secs(2)).await;
    }
}

pub fn set_volume(ctx: &Ctx, volume: f64) {
    let ctx2 = ctx.clone();
    ctx.spawn(async move {
        let v = format!("{:.2}", volume.clamp(0.0, 1.0));
        let _ = async_process::Command::new("wpctl").args(["set-volume", "@DEFAULT_AUDIO_SINK@", &v]).status().await;
        ctx2.publish(store::Diff::Devices(Diff::Audio(read_volume().await)));
    });
}

pub fn toggle_mute(ctx: &Ctx) {
    let ctx2 = ctx.clone();
    ctx.spawn(async move {
        let _ = async_process::Command::new("wpctl").args(["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]).status().await;
        ctx2.publish(store::Diff::Devices(Diff::Audio(read_volume().await)));
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wpctl_lines() {
        assert_eq!(parse_wpctl("Volume: 0.40\n"), Some(Audio { volume: Some(0.4), muted: false, name: String::new() }));
        assert_eq!(parse_wpctl("Volume: 1.00 [MUTED]\n"), Some(Audio { volume: Some(1.0), muted: true, name: String::new() }));
        assert_eq!(parse_wpctl("error"), None);
        let inspect = "id 52, type PipeWire:Interface:Node\n  * node.description = \"Virtual Sink\"\n    node.name = \"auto_null\"\n";
        assert_eq!(parse_inspect(inspect), "Virtual Sink");
        assert_eq!(parse_inspect("    node.name = \"auto_null\"\n"), "auto_null");
    }
}
