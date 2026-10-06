//! A panel whose body has not been ported yet: its own header (icon,
//! title, width and header controls, as its QML file has them) over an
//! empty body that holds the card at a working depth. Each one is replaced
//! by its own module in R3 Tasks 2 to 5, R7 and R8.

use super::{Effect, Panel, View};
use crate::services::devices;
use crate::store::Topic;
use crate::ui::{El, Event, What, w};

pub struct StandIn {
    id: &'static str,
}

impl StandIn {
    pub fn new(id: &'static str) -> Self {
        Self { id }
    }
}

/// Each panel's `panelTitle` and `panelIcon`.
fn header(id: &str) -> (&'static str, &'static str) {
    match id {
        "appmenu" => ("App menu", "menu"),
        "calendar" => ("Calendar", "calendar"),
        "network" => ("Wi-Fi", "wifi"),
        "iphone" => ("iPhone", "smartphone"),
        "power" => ("Power", "zap"),
        "weather" => ("Weather", "cloud"),
        "media" => ("Media", "music"),
        "github" => ("GitHub", "git-branch"),
        "usage" => ("Usage", "gauge"),
        "tailscale" => ("Tailscale", "network"),
        "systemupdate" => ("System update", "package"),
        "display" => ("Display", "monitor"),
        "monitor" => ("Monitor", "activity"),
        "trayoverflow" => ("Tray", "ellipsis"),
        "radio" => ("Radio", "radio"),
        _ => ("", ""),
    }
}

impl Panel for StandIn {
    fn id(&self) -> &'static str {
        self.id
    }

    fn title(&self, _: &View) -> String {
        header(self.id).0.into()
    }

    fn icon(&self, _: &View) -> String {
        header(self.id).1.into()
    }

    fn reads(&self) -> &'static [Topic] {
        if self.id == "network" { &[Topic::Devices] } else { &[] }
    }

    fn width(&self, v: &View) -> f64 {
        let s = &v.theme.space;
        match self.id {
            "calendar" | "monitor" | "media" => s.popup_width_wide,
            _ => s.popup_width_default,
        }
    }

    fn actions(&self, v: &View) -> Vec<El> {
        match self.id {
            // NetworkPanel.qml's: the radio is a state, rescan an action.
            "network" => {
                let n = &v.store.devices.network;
                vec![w::switch(n.wifi_enabled).on("radio"), w::icon_button("refresh-cw").tip("Rescan").on("rescan").key("rescan")]
            }
            "calendar" => vec![w::icon_button("chevron-left").key("previous"), w::icon_button("chevron-right").key("next")],
            _ => Vec::new(),
        }
    }

    fn body(&self, v: &View) -> El {
        let s = &v.theme.space;
        w::column(0.0, vec![w::space(s.control_height * 5.0)])
    }

    fn event(&mut self, ev: &Event, fx: &mut Effect) {
        match (ev.on.as_str(), &ev.what) {
            ("radio", What::Toggle(on)) => {
                let on = *on;
                fx.service(move |ctx| devices::run(ctx, devices::Op::Wifi(on)));
            }
            ("rescan", What::Click) => fx.service(|ctx| devices::run(ctx, devices::Op::Rescan)),
            _ => {}
        }
    }
}
