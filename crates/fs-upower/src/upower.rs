use std::collections::HashMap;

use futures_lite::{Stream, StreamExt, stream};
use zbus::fdo::PropertiesProxy;
use zbus::message::Type;
use zbus::names::InterfaceName;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};
use zbus::{Connection, MatchRule, MessageStream, proxy};

use crate::device::Device;

const SERVICE: &str = "org.freedesktop.UPower";
const ROOT_PATH: &str = "/org/freedesktop/UPower";
const DEVICE_INTERFACE: &str = "org.freedesktop.UPower.Device";
const DISPLAY_DEVICE_PATH: &str = "/org/freedesktop/UPower/devices/DisplayDevice";

#[proxy(
    interface = "org.freedesktop.UPower",
    default_service = "org.freedesktop.UPower",
    default_path = "/org/freedesktop/UPower",
    gen_blocking = false
)]
trait Root {
    fn enumerate_devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    fn get_display_device(&self) -> zbus::Result<OwnedObjectPath>;

    #[zbus(property)]
    fn on_battery(&self) -> zbus::Result<bool>;
}

/// Everything UPower reports, read once.
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    /// Every enumerated device, line power and peripherals included.
    pub devices: Vec<Device>,
    /// UPower's aggregate. On a machine with no battery it is present in the
    /// answer but `is_present` is false and `is_laptop_battery()` fails.
    pub display: Device,
    pub on_battery: bool,
}

/// One change out of [`UPower::changes`]. Each carries the value after the
/// change, so the consumer replaces rather than patches.
#[derive(Debug, Clone, PartialEq)]
pub enum Change {
    DeviceAdded(Device),
    DeviceRemoved(OwnedObjectPath),
    Device(Device),
    Display(Device),
    OnBattery(bool),
}

#[derive(Clone)]
pub struct UPower {
    conn: Connection,
    root: RootProxy<'static>,
}

impl UPower {
    /// Bus-activates upowerd when it is not running yet.
    pub async fn connect(conn: &Connection) -> zbus::Result<Self> {
        let root = RootProxy::new(conn).await?;
        Ok(Self {
            conn: conn.clone(),
            root,
        })
    }

    pub async fn devices(&self) -> zbus::Result<Vec<Device>> {
        let mut out = Vec::new();
        for path in self.root.enumerate_devices().await? {
            // A device can vanish between the enumerate and the read.
            if let Ok(device) = read_device(&self.conn, &mut Props::new(), path).await {
                out.push(device);
            }
        }
        Ok(out)
    }

    pub async fn display_device(&self) -> zbus::Result<Device> {
        read_device(&self.conn, &mut Props::new(), self.root.get_display_device().await?).await
    }

    pub async fn on_battery(&self) -> zbus::Result<bool> {
        self.root.on_battery().await
    }

    pub async fn snapshot(&self) -> zbus::Result<Snapshot> {
        Ok(Snapshot {
            devices: self.devices().await?,
            display: self.display_device().await?,
            on_battery: self.on_battery().await?,
        })
    }

    /// Device added and removed, `OnBattery`, and every property change of any
    /// device, until the connection closes. The match rule is installed
    /// before this resolves, so nothing between the call and the first poll
    /// is lost. A device's properties are read whole once; after that each
    /// `PropertiesChanged` is applied from its own payload, with no call back.
    pub async fn changes(&self) -> zbus::Result<impl Stream<Item = Change> + use<>> {
        let rule = MatchRule::builder()
            .msg_type(Type::Signal)
            .sender(SERVICE)?
            .build();
        let messages = MessageStream::for_match_rule(rule, &self.conn, None).await?;
        let conn = self.conn.clone();
        Ok(stream::unfold((conn, messages, Props::new()), |(conn, mut messages, mut known)| async move {
            loop {
                let message = messages.next().await?.ok()?;
                if let Some(change) = classify(&conn, &mut known, &message).await {
                    return Some((change, (conn, messages, known)));
                }
            }
        }))
    }
}

/// Every device's properties as last read or changed, by path.
type Props = HashMap<String, HashMap<String, OwnedValue>>;

async fn classify(conn: &Connection, known: &mut Props, message: &zbus::Message) -> Option<Change> {
    let header = message.header();
    let member = header.member()?.as_str();
    let path = header.path()?.clone();
    match (header.interface()?.as_str(), member) {
        ("org.freedesktop.UPower", "DeviceAdded") => {
            let added: OwnedObjectPath = message.body().deserialize().ok()?;
            read_device(conn, known, added).await.ok().map(Change::DeviceAdded)
        }
        ("org.freedesktop.UPower", "DeviceRemoved") => {
            let removed: OwnedObjectPath = message.body().deserialize().ok()?;
            known.remove(removed.as_str());
            Some(Change::DeviceRemoved(removed))
        }
        ("org.freedesktop.DBus.Properties", "PropertiesChanged") => {
            let (_, changed, invalidated): (String, HashMap<String, OwnedValue>, Vec<String>) =
                message.body().deserialize().ok()?;
            if path.as_str() == ROOT_PATH {
                return match crate::device::get::<bool>(&changed, "OnBattery") {
                    Some(on) => Some(Change::OnBattery(on)),
                    None if invalidated.iter().any(|k| k == "OnBattery") => {
                        RootProxy::new(conn).await.ok()?.on_battery().await.ok().map(Change::OnBattery)
                    }
                    None => None,
                };
            }
            let device = match known.get_mut(path.as_str()) {
                Some(props) if invalidated.is_empty() => {
                    props.extend(changed);
                    Device::from_properties(path.clone().into(), props)
                }
                _ => read_device(conn, known, path.clone().into()).await.ok()?,
            };
            Some(if path.as_str() == DISPLAY_DEVICE_PATH {
                Change::Display(device)
            } else {
                Change::Device(device)
            })
        }
        _ => None,
    }
}

async fn read_device(conn: &Connection, known: &mut Props, path: OwnedObjectPath) -> zbus::Result<Device> {
    let props = PropertiesProxy::builder(conn)
        .destination(SERVICE)?
        .path(path.clone())?
        .build()
        .await?;
    let all = props
        .get_all(InterfaceName::from_static_str_unchecked(DEVICE_INTERFACE))
        .await?;
    let device = Device::from_properties(path.clone(), &all);
    known.insert(path.to_string(), all);
    Ok(device)
}

