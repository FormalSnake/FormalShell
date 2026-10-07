//! Indicators.qml: the things running in the background, each an icon that
//! only exists while it runs. The QML rail makes each its own cell; here
//! they share one, spaced as the rail spaces them, with one tooltip naming
//! all and a click reaching the one under the pointer. A service joins by
//! adding one block to [`items`].

use std::time::{Duration, Instant};

use fs_info::reminders;
use fs_system::capture::elapsed_label;

use crate::services::notifications::now_ms;
use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, Part, Tone, View};

#[derive(Clone, Debug, PartialEq)]
struct Item {
    icon: &'static str,
    /// A dim countdown beside the icon.
    label: Option<String>,
    tooltip: String,
    destructive: bool,
    /// Drawn dim: the thing is winding down.
    dim: bool,
    /// What a click on it does.
    click: Option<Action>,
}

impl Item {
    fn new(icon: &'static str, tooltip: impl Into<String>) -> Self {
        Self { icon, label: None, tooltip: tooltip.into(), destructive: false, dim: false, click: None }
    }

    fn parts(&self) -> usize {
        1 + usize::from(self.label.is_some())
    }
}

/// Every indicator that is up, in the rail's order: the loud ones lead.
fn items(env: &Env) -> Vec<Item> {
    let mut out = Vec::new();
    let rec = &env.store.recording;
    if rec.active {
        out.push(Item {
            destructive: true,
            dim: rec.stopping,
            ..Item::new("circle-dot", format!("RECORDING {}", elapsed_label(rec.elapsed_ms as f64)))
        });
    }
    let clipssh = &env.store.clipssh.target;
    if !clipssh.is_empty() {
        out.push(Item::new("terminal", format!("SENDING CLIPBOARD IMAGE TO {clipssh}")));
    }
    let airplay = &env.store.media.airplay;
    if airplay.active {
        let from = if airplay.client.is_empty() { String::new() } else { format!(" FROM {}", airplay.client) };
        out.push(Item::new("airplay", format!("AIRPLAY{from}")));
    }
    let pending = &env.store.notifications.reminders;
    if let Some(first) = pending.first() {
        out.push(Item {
            label: Some(reminders::bar_label(pending, now_ms() as f64)),
            click: Some(Action::ReminderSummary),
            ..Item::new("alarm-clock", format!("{} / {}", first.message, reminders::bar_label(pending, now_ms() as f64)))
        });
    }
    if env.store.caffeinate.active {
        out.push(Item { click: Some(Action::Caffeinate(false)), ..Item::new("coffee", "CAFFEINATE ON") });
    }
    if env.store.nightlight.active {
        out.push(Item::new("lightbulb", "NIGHT LIGHT ON"));
    }
    if !env.store.state.data.overnight.is_null() {
        out.push(Item { click: Some(Action::OvernightOff), ..Item::new("moon-star", "OVERNIGHT ON") });
    }
    out
}

#[derive(Default)]
pub struct Indicators {
    items: Vec<Item>,
    /// Where each item ends along the strip, past the leading padding, and
    /// the gap to the next, as the last measure laid them out.
    ends: Vec<f64>,
    /// The leading padding, the gap between items and the one between an
    /// item's own parts, as the last view laid them.
    geometry: std::cell::Cell<(f64, f64, f64)>,
    vertical: bool,
    /// The countdown's next second, while a reminder is pending.
    tick: Option<Instant>,
}

impl Cell for Indicators {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Caffeinate, Topic::Recording, Topic::Clipssh, Topic::NightLight, Topic::State, Topic::Media, Topic::Notifications]
    }

    fn read(&mut self, env: &Env) -> bool {
        let items = items(env);
        let vertical = env.edge.is_vertical();
        // An unrelated change must not slide the countdown's next second away.
        let now = Instant::now();
        self.tick = match (items.iter().any(|i| i.label.is_some()), self.tick) {
            (false, _) => None,
            (true, Some(due)) if due > now => Some(due),
            (true, _) => Some(now + Duration::from_secs(1)),
        };
        let changed = items != self.items || vertical != self.vertical;
        (self.items, self.vertical) = (items, vertical);
        changed
    }

    fn view(&self, look: &Look) -> View {
        if self.items.is_empty() {
            return View::hidden();
        }
        // The rail's gap, with each icon's own cell padding either side;
        // an item's own parts sit `xxs` apart.
        let gap = look.sm + look.pad_x * 2.0;
        let mut parts = Vec::new();
        for (n, item) in self.items.iter().enumerate() {
            if n > 0 {
                parts.push(Part::Pad(gap - look.xxs * 2.0));
            }
            parts.push(Part::Icon { name: item.icon.into(), dim: item.dim, dot: false });
            if let Some(label) = &item.label {
                parts.push(Part::DimLabel { text: label.clone() });
            }
        }
        let tooltip = self.items.iter().map(|i| i.tooltip.as_str()).collect::<Vec<_>>().join(" / ");
        let mut view = View::new(parts, look.xxs).tooltip(tooltip);
        if self.items.iter().any(|i| i.destructive) {
            view = view.tone(Tone::Destructive);
        }
        view.interactive = self.items.iter().any(|i| i.click.is_some());
        self.geometry.set((look.pad_x, gap, look.xxs));
        view
    }

    fn laid(&mut self, extents: &[f64]) {
        let (_, _, xxs) = self.geometry.get();
        let mut parts = extents.iter().copied();
        let (mut at, mut first) = (0.0, true);
        let mut step = |ext: f64| {
            if !first {
                at += xxs;
            }
            first = false;
            at += ext;
            at
        };
        let mut ends = Vec::new();
        for (n, item) in self.items.iter().enumerate() {
            if n > 0 {
                step(parts.next().unwrap_or(0.0));
            }
            let mut end = 0.0;
            for _ in 0..item.parts() {
                end = step(parts.next().unwrap_or(0.0));
            }
            ends.push(end);
        }
        self.ends = ends;
    }

    fn wake(&self) -> Option<Instant> {
        self.tick
    }

    fn click(&mut self, _: Button, at: (f64, f64), _: &Env) -> Action {
        let (lead, gap, _) = self.geometry.get();
        let along = (if self.vertical { at.1 } else { at.0 }) - lead;
        let index = self.ends.iter().position(|end| along < end + gap / 2.0).unwrap_or(self.items.len().saturating_sub(1));
        self.items.get(index).and_then(|i| i.click.clone()).unwrap_or(Action::None)
    }
}
