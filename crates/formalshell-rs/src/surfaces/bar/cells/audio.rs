//! AudioWidget.qml: the default sink's volume, muted or not; the wheel
//! steps it by 5%.

use crate::services::devices;
use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, View};

#[derive(Default)]
pub struct Audio {
    state: devices::Audio,
}

impl Cell for Audio {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Devices]
    }

    fn read(&mut self, env: &Env) -> bool {
        let state = env.store.devices.audio.clone();
        let changed = state != self.state;
        self.state = state;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let s = &self.state;
        let percent = (s.volume.unwrap_or(0.0) * 100.0).round();
        let head = if s.muted { "OUTPUT MUTED" } else { "OUTPUT VOLUME" };
        View::icon(if s.muted { "volume-x" } else { "volume-2" }, look)
            .panel("audio")
            .tooltip(format!("{head} / {percent}% / RIGHT MUTE"))
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Right => Action::ToggleMute,
            _ => Action::Panel("audio"),
        }
    }

    fn wheel(&mut self, up: bool, _: &Env) -> Action {
        let v = self.state.volume.unwrap_or(0.0);
        Action::Volume(v + if up { 0.05 } else { -0.05 })
    }
}
