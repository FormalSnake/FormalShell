//! NetworkManager through fs-network, what NetworkWidget.qml reads: wired or
//! Wi-Fi connected, the network the Wi-Fi device is on, and the radio
//! switch.

use std::cell::RefCell;

use fs_network::{DeviceKind, NetworkManager, Snapshot};
use futures_lite::StreamExt;

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Network {
    /// False until NetworkManager has answered.
    pub known: bool,
    pub wired: bool,
    pub wifi: bool,
    pub wifi_enabled: bool,
    /// The connected network's SSID and signal, in percent.
    pub ssid: Option<(String, u8)>,
}

thread_local! {
    static NM: RefCell<Option<NetworkManager>> = const { RefCell::new(None) };
}

fn view(s: &Snapshot) -> Network {
    let up = |kind| s.devices.iter().any(|d| d.kind == kind && d.connected());
    Network {
        known: true,
        wired: up(DeviceKind::Wired),
        wifi: up(DeviceKind::Wifi),
        wifi_enabled: s.wifi_enabled,
        ssid: s.networks.iter().find(|n| n.connected()).map(|n| (n.ssid.clone(), n.signal.as_percent())),
    }
}

pub async fn run(ctx: Ctx) {
    let publish = |n| ctx.publish(store::Diff::Devices(super::Diff::Network(n)));
    let Ok(conn) = zbus::Connection::system().await else { return publish(Network::default()) };
    let nm = match NetworkManager::connect(&conn).await {
        Ok(nm) => nm,
        Err(err) => {
            eprintln!("network: {err}");
            return publish(Network::default());
        }
    };
    let mut changes = match nm.changes().await {
        Ok(changes) => Box::pin(changes),
        Err(err) => {
            eprintln!("network: {err}");
            return publish(Network::default());
        }
    };
    NM.with_borrow_mut(|n| *n = Some(nm));
    while let Some(snapshot) = changes.next().await {
        publish(view(&snapshot));
    }
}

/// NetworkManager's radio switch, set outright.
pub fn set_wifi(ctx: &Ctx, on: bool) {
    let Some(nm) = NM.with_borrow(|n| n.clone()) else { return };
    ctx.spawn(async move {
        if let Err(err) = nm.set_wifi_enabled(on).await {
            eprintln!("network: {err}");
        }
    });
}

/// `RequestScan` on every Wi-Fi device NetworkManager has.
pub fn rescan(ctx: &Ctx) {
    let Some(nm) = NM.with_borrow(|n| n.clone()) else { return };
    ctx.spawn(async move {
        if let Err(err) = nm.request_scan().await {
            eprintln!("network: {err}");
        }
    });
}

/// NetworkWidget.qml's right click: `Networking.wifiEnabled` flipped.
pub fn toggle_wifi(ctx: &Ctx) {
    let Some(nm) = NM.with_borrow(|n| n.clone()) else { return };
    ctx.spawn(async move {
        let result = match nm.snapshot().await {
            Ok(s) => nm.set_wifi_enabled(!s.wifi_enabled).await,
            Err(err) => Err(err),
        };
        if let Err(err) = result {
            eprintln!("network: {err}");
        }
    });
}
