//! Indicators.qml: the things running in the background, each an icon that
//! only exists while it runs. The QML rail makes each its own cell; here
//! they share one, spaced as the rail spaces them, with one tooltip naming
//! all and a click reaching the one under the pointer. A service joins by
//! adding one block to [`items`].

use std::cell::Cell as Mutable;

use fs_system::capture::elapsed_label;

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, Part, Tone, View};

#[derive(Clone, Debug, PartialEq)]
struct Item {
    icon: &'static str,
    tooltip: String,
    destructive: bool,
    /// Drawn dim: the thing is winding down.
    dim: bool,
    /// What a click on it does.
    click: Option<Action>,
}

/// Every indicator that is up, in the rail's order.
fn items(env: &Env) -> Vec<Item> {
    let mut out = Vec::new();
    let rec = &env.store.recording;
    if rec.active {
        out.push(Item {
            icon: "circle-dot",
            tooltip: format!("RECORDING {}", elapsed_label(rec.elapsed_ms as f64)),
            destructive: true,
            dim: rec.stopping,
            click: None,
        });
    }
    let clipssh = &env.store.clipssh.target;
    if !clipssh.is_empty() {
        out.push(Item { icon: "terminal", tooltip: format!("SENDING CLIPBOARD IMAGE TO {clipssh}"), destructive: false, dim: false, click: None });
    }
    if env.store.caffeinate.active {
        out.push(Item { icon: "coffee", tooltip: "CAFFEINATE ON".into(), destructive: false, dim: false, click: Some(Action::Caffeinate(false)) });
    }
    out
}

#[derive(Default)]
pub struct Indicators {
    items: Vec<Item>,
    /// The icon pitch, the leading padding and the gap between icons along
    /// the strip, as the last view laid them, for a click to find its icon.
    pitch: Mutable<(f64, f64, f64)>,
    vertical: bool,
}

impl Cell for Indicators {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Caffeinate, Topic::Recording, Topic::Clipssh]
    }

    fn read(&mut self, env: &Env) -> bool {
        let items = items(env);
        let vertical = env.edge.is_vertical();
        let changed = items != self.items || vertical != self.vertical;
        (self.items, self.vertical) = (items, vertical);
        changed
    }

    fn view(&self, look: &Look) -> View {
        if self.items.is_empty() {
            return View::hidden();
        }
        // The rail's gap, with each icon's own cell padding either side.
        let gap = look.sm + look.pad_x * 2.0;
        self.pitch.set((look.body as f64 + gap, look.pad_x, gap));
        let parts = self.items.iter().map(|i| Part::Icon { name: i.icon.into(), dim: i.dim, dot: false }).collect();
        let tooltip = self.items.iter().map(|i| i.tooltip.as_str()).collect::<Vec<_>>().join(" / ");
        let mut view = View::new(parts, gap).tooltip(tooltip);
        if self.items.iter().any(|i| i.destructive) {
            view = view.tone(Tone::Destructive);
        }
        view.interactive = self.items.iter().any(|i| i.click.is_some());
        view
    }

    fn click(&mut self, _: Button, at: (f64, f64), _: &Env) -> Action {
        let (pitch, lead, gap) = self.pitch.get();
        let along = if self.vertical { at.1 } else { at.0 };
        let index = ((along - lead + gap / 2.0) / pitch).floor().max(0.0) as usize;
        self.items.get(index.min(self.items.len() - 1)).and_then(|i| i.click.clone()).unwrap_or(Action::None)
    }
}
