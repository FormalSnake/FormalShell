//! BlueZ through fs-bluez: the default adapter's state for the bar cell,
//! and the device list the earbuds backends cross their own lists with.

use std::cell::RefCell;

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Bluetooth {
    /// None with no adapter (or no bluetoothd).
    pub powered: Option<bool>,
    pub connected: Vec<String>,
}

thread_local! {
    static BLUEZ: RefCell<Option<fs_bluez::Bluez>> = const { RefCell::new(None) };
}

fn snapshot(state: &fs_bluez::state::State) -> Bluetooth {
    let Some(adapter) = state.default_adapter() else { return Bluetooth::default() };
    let connected = state
        .devices_of(&adapter.path)
        .into_iter()
        .filter(|d| d.info.connected)
        .map(|d| if d.info.name.is_empty() { d.info.device_name } else { d.info.name })
        .collect();
    Bluetooth { powered: Some(adapter.powered), connected }
}

fn smoke_override() -> Option<String> {
    std::env::var("FORMALSHELL_SMOKE_BLUETOOTH").ok()
}

fn publish(ctx: &Ctx, bt: Bluetooth, devices: Vec<fs_devices::bluetooth::Device>) {
    ctx.publish(store::Diff::Devices(super::Diff::Bluetooth(bt)));
    super::earbuds::bluetooth(devices);
}

fn absent(ctx: &Ctx) {
    let devices = fs_devices::earbuds::bluetooth_devices(&[], smoke_override().as_deref());
    publish(ctx, Bluetooth::default(), devices);
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
    publish(&ctx, snapshot(&bluez.state()), bluez.earbuds_devices(over.as_deref()));
    BLUEZ.with_borrow_mut(|b| *b = Some(bluez.clone()));
    while events.recv().await.is_ok() {
        while events.try_recv().is_ok() {}
        publish(&ctx, snapshot(&bluez.state()), bluez.earbuds_devices(over.as_deref()));
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
