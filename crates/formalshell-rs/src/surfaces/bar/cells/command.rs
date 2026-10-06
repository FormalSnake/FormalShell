//! CommandModule.qml: a `bar.modules` command's last answer as a label,
//! its `class` as the cell's tone; an empty answer is no cell at all. The
//! runs themselves are the commands service's. A `qml` module has no engine
//! to load into here and says so.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Cell, Env, Look, Part, Tone, View};

pub struct Command {
    id: String,
    qml: bool,
    out: crate::services::commands::Output,
}

impl Command {
    pub fn new(id: &str) -> Self {
        Self { id: id.to_owned(), qml: false, out: Default::default() }
    }

    pub fn qml(id: &str) -> Self {
        let out = crate::services::commands::Output {
            text: "MODULE ERROR".into(),
            tooltip: "QML MODULES RUN ONLY IN THE QML SHELL".into(),
            class: String::new(),
        };
        Self { id: id.to_owned(), qml: true, out }
    }
}

impl Cell for Command {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Commands]
    }

    fn read(&mut self, env: &Env) -> bool {
        if self.qml {
            return false;
        }
        let out = env.store.commands.outputs.get(&self.id).cloned().unwrap_or_default();
        let changed = out != self.out;
        self.out = out;
        changed
    }

    fn view(&self, look: &Look) -> View {
        if self.out.text.is_empty() {
            return View::hidden();
        }
        let tone = match self.out.class.as_str() {
            "warning" => Tone::Warning,
            "critical" | "urgent" => Tone::Destructive,
            _ => Tone::Rest,
        };
        let mut view = View::new(vec![Part::Label { text: self.out.text.clone(), weight: Some(400.0) }], look.xxs)
            .tone(tone)
            .tooltip(self.out.tooltip.clone());
        view.interactive = false;
        view
    }
}
