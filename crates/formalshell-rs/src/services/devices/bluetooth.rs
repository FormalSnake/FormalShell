//! BlueZ through fs-bluez: the default adapter's state for the bar cell,
//! and the device list the earbuds backends cross their own lists with.

use std::cell::RefCell;

use async_channel::Receiver;
use futures_lite::{FutureExt, future};

use super::headsets::{self, Headset};
use crate::runtime::Ctx;
use crate::services::watch::Watch;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Bluetooth {
    /// None with no adapter (or no bluetoothd).
    pub powered: Option<bool>,
    pub connected: Vec<String>,
    /// The Bluetooth audio devices, connected or not; none until BlueZ (or
    /// its absence) has answered once.
    pub headsets: Option<Vec<Headset>>,
}

thread_local! {
    static BLUEZ: RefCell<Option<fs_bluez::Bluez>> = const { RefCell::new(None) };
}

fn snapshot(state: &fs_bluez::state::State, over: Option<&str>) -> Bluetooth {
    let headsets = Some(headsets::read(Some(state), over));
    let Some(adapter) = state.default_adapter() else { return Bluetooth { headsets, ..Bluetooth::default() } };
    let connected = state
        .devices_of(&adapter.path)
        .into_iter()
        .filter(|d| d.info.connected)
        .map(|d| if d.info.name.is_empty() { d.info.device_name } else { d.info.name })
        .collect();
    Bluetooth { powered: Some(adapter.powered), connected, headsets }
}

fn smoke_override() -> Option<String> {
    headsets::smoke_text()
}

/// Signals each change of the file an `@path` override names.
fn smoke_changes(ctx: &Ctx) -> Option<Receiver<()>> {
    let mut watch = Watch::new(headsets::smoke_file()?).ok()?;
    let (tx, rx) = async_channel::unbounded();
    ctx.spawn(async move {
        loop {
            watch.changed().await;
            if tx.send(()).await.is_err() {
                return;
            }
        }
    });
    Some(rx)
}

fn publish(ctx: &Ctx, bt: Bluetooth, devices: Vec<fs_devices::bluetooth::Device>) {
    ctx.publish(store::Diff::Devices(super::Diff::Bluetooth(bt)));
    super::earbuds::bluetooth(devices);
}

fn absent(ctx: &Ctx) {
    let over = smoke_override();
    let devices = fs_devices::earbuds::bluetooth_devices(&[], over.as_deref());
    publish(ctx, Bluetooth { headsets: Some(headsets::read(None, over.as_deref())), ..Bluetooth::default() }, devices);
}

pub async fn run(ctx: Ctx) {
    let Ok(conn) = zbus::Connection::system().await else { return absent(&ctx) };
    let (bluez, events, monitor) = match fs_bluez::Bluez::connect(&conn).await {
        Ok(v) => v,
        Err(err) => {
            eprintln!("bluetooth: {err}");
            return absent(&ctx);
        }
    };
    ctx.spawn(monitor.run());
    let over = smoke_override();
    publish(&ctx, snapshot(&bluez.state(), over.as_deref()), bluez.earbuds_devices(over.as_deref()));
    BLUEZ.with_borrow_mut(|b| *b = Some(bluez.clone()));
    let changes = smoke_changes(&ctx);
    loop {
        let bluez_event = async { events.recv().await.is_ok() };
        let file_event = async {
            match &changes {
                Some(rx) => rx.recv().await.is_ok(),
                None => future::pending().await,
            }
        };
        if !bluez_event.or(file_event).await {
            break;
        }
        while events.try_recv().is_ok() {}
        let over = smoke_override();
        publish(&ctx, snapshot(&bluez.state(), over.as_deref()), bluez.earbuds_devices(over.as_deref()));
    }
}

/// BluetoothWidget.qml's right click: the default adapter's radio flipped.
pub fn toggle_power(ctx: &Ctx) {
    let Some(bluez) = BLUEZ.with_borrow(|b| b.clone()) else { return };
    ctx.spawn(async move {
        let Some(adapter) = bluez.state().default_adapter().cloned() else { return };
        if let Err(err) = bluez.set_powered(&adapter.path, !adapter.powered).await {
            eprintln!("bluetooth: {err}");
        }
    });
}

/// Trusts the device at `address`: BlueZ otherwise asks an agent to
/// authorize every profile on each reconnect (the iPhone service, once a
/// pairing lands).
pub fn trust(ctx: &Ctx, address: &str) {
    let Some(bluez) = BLUEZ.with_borrow(|b| b.clone()) else { return };
    let address = address.to_owned();
    ctx.spawn(async move {
        if let Err(err) = bluez.set_trusted(&address, true).await {
            eprintln!("bluetooth: {err}");
        }
    });
}
