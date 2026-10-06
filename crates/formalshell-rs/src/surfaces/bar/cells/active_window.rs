//! ActiveWindow.qml: the held-focus window's app name, elided at half a
//! narrow popup, then its title as the strip's second free label. With no
//! desktop entry resolved the name is the app id in the meta ink.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Limits, Look, Part, View};

#[derive(Default)]
pub struct ActiveWindow {
    window: Option<(String, String)>,
}

impl Cell for ActiveWindow {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Hyprland]
    }

    fn read(&mut self, env: &Env) -> bool {
        let h = &env.store.hyprland;
        let held = h.held_focused_window_id();
        let window = h.window(&held).map(|w| (w.app_id.clone(), w.title.clone()));
        let changed = window != self.window;
        self.window = window;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let Some((app_id, title)) = &self.window else { return View::hidden() };
        View::new(
            vec![
                Part::Name { text: app_id.clone(), max: look.narrow / 2.0, dim: true },
                Part::Free { text: title.clone(), dim: false, lead: look.md, ceiling: f64::INFINITY },
            ],
            look.xxs,
        )
    }

    fn limits(&self, look: &Look, _along: f64, rest: f64) -> Option<Limits> {
        Some(Limits { cap: (look.narrow - rest).max(0.0), min: look.cell_width * 2.0 })
    }

    fn click(&mut self, _: Button, _: (f64, f64), _: &Env) -> Action {
        Action::Panel("appmenu")
    }
}
