//! NetworkWidget.qml: wired, Wi-Fi or offline, as one icon.

use crate::services::devices;
use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, View};

#[derive(Default)]
pub struct Network {
    state: devices::Network,
}

impl Cell for Network {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Devices]
    }

    fn read(&mut self, env: &Env) -> bool {
        let state = env.store.devices.network.clone();
        let changed = state != self.state;
        self.state = state;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let s = &self.state;
        let icon = if s.wired {
            "globe"
        } else if s.wifi {
            "wifi"
        } else {
            "wifi-off"
        };
        let head = if s.wired {
            "NETWORK / WIRED"
        } else if s.wifi {
            "WI-FI / CONNECTED"
        } else {
            "NETWORK / OFFLINE"
        };
        let tooltip = format!("{head} / RIGHT {}", if s.wifi_enabled { "WI-FI OFF" } else { "WI-FI ON" });
        View::icon(icon, look).panel("network").tooltip(tooltip)
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Right => Action::None,
            _ => Action::Panel("network"),
        }
    }
}
