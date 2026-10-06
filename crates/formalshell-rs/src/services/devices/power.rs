//! UPower through fs-upower: the laptop battery Battery.qml reads off the
//! display device, `OnBattery`, and the DualSense battery. hid-playstation's
//! `ps-controller-battery-<MAC>` supply is one of UPower's own devices, so
//! the controller arrives and changes on UPower's signals rather than on
//! DualsenseService.qml's 30 second sysfs poll.

use std::collections::BTreeMap;

use fs_system::dualsense::{self, Supply};
use fs_system::power::model::DeviceState;
use fs_upower::{Change, Device, PowerProfiles, Profile, ProfilesState, UPower};
use futures_lite::StreamExt;

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, PartialEq)]
pub struct Battery {
    /// Whole percent, as the cell shows it.
    pub percent: f64,
    pub state: DeviceState,
    /// Watts, a magnitude (`changeRate`).
    pub rate: f64,
    /// Seconds, 0 when UPower has no estimate.
    pub time_to_full: f64,
    pub time_to_empty: f64,
    /// The pack's capacity against its design, off the physical battery:
    /// the display device is an aggregate and publishes none.
    pub health: Option<f64>,
    /// Watt-hours, 0 when UPower has no reading.
    pub size_wh: f64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Power {
    /// None without a laptop battery (`isLaptopBattery`), which hides the cell.
    pub battery: Option<Battery>,
    pub on_battery: bool,
    /// None while no DualSense is connected.
    pub dualsense: Option<Supply>,
}

fn state(s: fs_upower::DeviceState) -> DeviceState {
    use fs_upower::DeviceState as U;
    match s {
        U::Unknown => DeviceState::Unknown,
        U::Charging => DeviceState::Charging,
        U::Discharging => DeviceState::Discharging,
        U::Empty => DeviceState::Empty,
        U::FullyCharged => DeviceState::FullyCharged,
        U::PendingCharge => DeviceState::PendingCharge,
        U::PendingDischarge => DeviceState::PendingDischarge,
    }
}

fn battery(d: &Device, physical: Option<&Device>) -> Option<Battery> {
    let secs = |t: Option<std::time::Duration>| t.map_or(0.0, |t| t.as_secs_f64());
    d.is_laptop_battery().then(|| Battery {
        percent: d.percentage.rounded() as f64,
        state: state(d.state),
        rate: d.energy_rate,
        time_to_full: secs(d.time_to_full),
        time_to_empty: secs(d.time_to_empty),
        health: physical.and_then(|p| p.capacity).map(|c| c.as_percent()),
        size_wh: d.energy_full,
    })
}

/// The supply's `status` word UPower read its state from, which is what
/// the cell's tooltip names.
fn status_word(s: fs_upower::DeviceState) -> &'static str {
    use fs_upower::DeviceState as U;
    match s {
        U::Charging => "Charging",
        U::Discharging | U::Empty => "Discharging",
        U::FullyCharged => "Full",
        U::PendingCharge | U::PendingDischarge => "Not charging",
        U::Unknown => "Unknown",
    }
}

/// First match wins, as the QML probe's `head -n1` did.
fn dualsense(devices: &BTreeMap<String, Device>) -> Option<Supply> {
    let d = devices.values().find(|d| d.native_path.starts_with("ps-controller-battery-") && d.is_present)?;
    let supply = dualsense::parse_supply(Some(&d.percentage.rounded().to_string()), Some(status_word(d.state)));
    (supply.percent >= 0).then_some(supply)
}

struct Seen {
    devices: BTreeMap<String, Device>,
    display: Option<Device>,
    on_battery: bool,
}

impl Seen {
    fn power(&self) -> Power {
        Power {
            battery: self.display.as_ref().and_then(|d| battery(d, self.devices.values().find(|d| d.is_laptop_battery()))),
            on_battery: self.on_battery,
            dualsense: dualsense(&self.devices),
        }
    }
}

pub async fn run(ctx: Ctx) {
    let publish = |p| ctx.publish(store::Diff::Devices(super::Diff::Power(p)));
    let Ok(conn) = zbus::Connection::system().await else { return publish(Power::default()) };
    let Ok(upower) = UPower::connect(&conn).await else { return publish(Power::default()) };
    // Subscribed before the snapshot, so nothing falls between the two.
    let changes = upower.changes().await;
    let Ok(snap) = upower.snapshot().await else { return publish(Power::default()) };
    let mut seen = Seen {
        devices: snap.devices.into_iter().map(|d| (d.path.to_string(), d)).collect(),
        display: Some(snap.display),
        on_battery: snap.on_battery,
    };
    publish(seen.power());
    let Ok(changes) = changes else { return };
    let mut changes = std::pin::pin!(changes);
    while let Some(change) = changes.next().await {
        match change {
            Change::DeviceAdded(d) | Change::Device(d) => {
                seen.devices.insert(d.path.to_string(), d);
            }
            Change::DeviceRemoved(path) => {
                seen.devices.remove(path.as_str());
            }
            Change::Display(d) => seen.display = Some(d),
            Change::OnBattery(on) => seen.on_battery = on,
        }
        publish(seen.power());
    }
}

/// power-profiles-daemon's active profile and the ones it offers, none
/// while the daemon is not on the bus.
pub async fn run_profiles(ctx: Ctx) {
    let publish = |p| ctx.publish(store::Diff::Devices(super::Diff::Profiles(p)));
    let Ok(conn) = zbus::Connection::system().await else { return publish(None) };
    let Ok(profiles) = PowerProfiles::connect(&conn).await else { return publish(None) };
    let Ok(changes) = profiles.changes().await else { return publish(None) };
    let mut changes = std::pin::pin!(changes);
    while let Some(state) = changes.next().await {
        publish(Some(state));
    }
}

/// The profile group's pick; a daemon that refuses leaves the live
/// property, and with it the group, where it was.
pub fn set_profile(ctx: &Ctx, profile: Profile) {
    ctx.spawn(async move {
        let Ok(conn) = zbus::Connection::system().await else { return };
        if let Ok(profiles) = PowerProfiles::connect(&conn).await {
            let _ = profiles.set_active(profile).await;
        }
    });
}

pub type Profiles = Option<ProfilesState>;
