//! BellWidget.qml: do-not-disturb and the pending count. A click opens or
//! shuts the notification centre, a right click flips DND.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, View};

#[derive(Default)]
pub struct Bell {
    dnd: bool,
    pending: usize,
}

impl Cell for Bell {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::State, Topic::Notifications]
    }

    fn read(&mut self, env: &Env) -> bool {
        let n = &env.store.notifications.model;
        let next = (n.dnd, n.pending.len());
        let changed = next != (self.dnd, self.pending);
        (self.dnd, self.pending) = next;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let tooltip = if self.dnd {
            "NOTIFICATIONS / DND ON".to_owned()
        } else if self.pending > 0 {
            format!("NOTIFICATIONS / {} PENDING", self.pending)
        } else {
            "NOTIFICATIONS / NONE PENDING".to_owned()
        };
        View::icon(if self.dnd { "bell-off" } else { "bell" }, look).tooltip(tooltip)
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Right => Action::Dnd(!self.dnd),
            _ => Action::Center,
        }
    }
}
