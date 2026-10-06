//! Clock.qml: the time as one mono label, stacked one piece per line on a
//! vertical bar, opening the calendar.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Action, Button, Cell, Env, Look, Part, View};

#[derive(Default)]
pub struct Clock {
    text: String,
    vertical: bool,
}

impl Cell for Clock {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Clock]
    }

    fn read(&mut self, env: &Env) -> bool {
        let (text, vertical) = (env.store.clock.text.clone(), env.edge.is_vertical());
        let changed = (text.as_str(), vertical) != (self.text.as_str(), self.vertical);
        (self.text, self.vertical) = (text, vertical);
        changed
    }

    fn view(&self, look: &Look) -> View {
        let pieces: Vec<&str> = if self.vertical {
            self.text.split([' ', ':', '-']).filter(|p| !p.is_empty()).collect()
        } else {
            vec![self.text.as_str()]
        };
        let parts = pieces.into_iter().map(|t| Part::Label { text: t.into(), weight: None }).collect();
        View::new(parts, if self.vertical { 0.0 } else { look.xs })
            .panel("calendar")
            .tooltip("RIGHT CYCLE FORMAT / MIDDLE CALENDAR")
    }

    fn click(&mut self, button: Button, _: (f64, f64), _: &Env) -> Action {
        match button {
            Button::Right => Action::None,
            _ => Action::Panel("calendar"),
        }
    }
}
