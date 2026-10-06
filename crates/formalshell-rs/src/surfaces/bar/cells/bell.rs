//! BellWidget.qml: do-not-disturb off state.json. The pending count is the
//! notification server's, and this shell holds no notifications yet, so
//! none are pending.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Cell, Env, Look, View};

#[derive(Default)]
pub struct Bell {
    dnd: bool,
}

impl Cell for Bell {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::State]
    }

    fn read(&mut self, env: &Env) -> bool {
        let dnd = env.store.state.data.dnd;
        let changed = dnd != self.dnd;
        self.dnd = dnd;
        changed
    }

    fn view(&self, look: &Look) -> View {
        let tooltip = if self.dnd { "NOTIFICATIONS / DND ON" } else { "NOTIFICATIONS / NONE PENDING" };
        View::icon(if self.dnd { "bell-off" } else { "bell" }, look).tooltip(tooltip)
    }
}
