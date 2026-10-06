use std::sync::{Arc, Mutex};

use zbus::{
    Connection, fdo, interface, message::Header, names::BusName, object_server::SignalEmitter,
};

pub(crate) const WATCHER_NAME: &str = "org.kde.StatusNotifierWatcher";
pub(crate) const WATCHER_PATH: &str = "/StatusNotifierWatcher";
pub(crate) const WATCHER_IFACE: &str = "org.kde.StatusNotifierWatcher";

#[derive(Default)]
pub(crate) struct WatcherState {
    pub items: Vec<String>,
    pub hosts: Vec<String>,
}

pub(crate) type SharedWatcher = Arc<Mutex<WatcherState>>;

pub(crate) struct Watcher {
    pub state: SharedWatcher,
}

/// Registered items are often missing the service or the path: a leading `/` means the sender
/// owns the item, no `/` means the default path.
pub(crate) fn qualify(item: &str, sender: Option<&str>) -> String {
    let mut q = match (item.starts_with('/'), sender) {
        (true, Some(s)) => format!("{s}{item}"),
        _ => item.to_owned(),
    };
    if !q.contains('/') {
        q.push_str("/StatusNotifierItem");
    }
    q
}

async fn has_owner(conn: &Connection, name: &str) -> bool {
    let Ok(bus_name) = BusName::try_from(name) else {
        return false;
    };
    let Ok(dbus) = fdo::DBusProxy::new(conn).await else {
        return false;
    };
    dbus.get_name_owner(bus_name).await.is_ok()
}

#[interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: &str,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        let key = qualify(service, header.sender().map(|s| s.as_str()));
        let name = key.split('/').next().unwrap_or_default().to_owned();
        if !has_owner(conn, &name).await {
            return Ok(());
        }
        {
            let mut st = self.state.lock().unwrap();
            if st.items.contains(&key) {
                return Ok(());
            }
            st.items.push(key.clone());
        }
        Self::status_notifier_item_registered(&emitter, &key).await?;
        Ok(())
    }

    async fn register_status_notifier_host(
        &self,
        service: &str,
        #[zbus(connection)] conn: &Connection,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        if !has_owner(conn, service).await {
            return Ok(());
        }
        {
            let mut st = self.state.lock().unwrap();
            if st.hosts.iter().any(|h| h == service) {
                return Ok(());
            }
            st.hosts.push(service.to_owned());
        }
        Self::status_notifier_host_registered(&emitter).await?;
        Ok(())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.state.lock().unwrap().items.clone()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_unregistered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// A service left the bus: drop what it registered and tell the other hosts.
pub(crate) async fn service_gone(conn: &Connection, state: &SharedWatcher, name: &str) {
    let (items, host) = {
        let mut st = state.lock().unwrap();
        let (gone, kept): (Vec<String>, Vec<String>) = std::mem::take(&mut st.items)
            .into_iter()
            .partition(|i| i.split('/').next() == Some(name));
        st.items = kept;
        let before = st.hosts.len();
        st.hosts.retain(|h| h != name);
        (gone, st.hosts.len() != before)
    };
    let Ok(emitter) = SignalEmitter::new(conn, WATCHER_PATH) else {
        return;
    };
    for key in items {
        let _ = Watcher::status_notifier_item_unregistered(&emitter, &key).await;
    }
    if host {
        let _ = Watcher::status_notifier_host_unregistered(&emitter).await;
    }
}
