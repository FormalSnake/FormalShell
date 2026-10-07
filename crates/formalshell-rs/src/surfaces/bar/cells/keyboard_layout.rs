//! A keyboard icon and the active layout's short
//! code. Hidden until the compositor has answered, and for a session with a
//! single layout; NO LAYOUT when it cannot be asked at all.

use fs_system::compositor::keyboard::{self, Layout};

use crate::store::Topic;
use crate::surfaces::bar::cell::{Cell, Env, Look, Part, View};

#[derive(Default)]
pub struct KeyboardLayout {
    layout: Option<Layout>,
    label: bool,
}

impl Cell for KeyboardLayout {
    fn reads(&self) -> &'static [Topic] {
        &[Topic::Hyprland]
    }

    fn read(&mut self, env: &Env) -> bool {
        let h = &env.store.hyprland;
        let layout = h.keyboard_answered.then(|| h.keyboard.clone());
        let label = env.store.config.bool("bar.widgets.keyboardLayout.showLabel").unwrap_or(true);
        let changed = layout != self.layout || label != self.label;
        (self.layout, self.label) = (layout, label);
        changed
    }

    fn view(&self, look: &Look) -> View {
        let Some(layout) = self.layout.as_ref().filter(|l| !l.available || keyboard::has_choice(l)) else {
            return View::hidden();
        };
        let mut parts = vec![Part::Icon { name: "keyboard".into(), dim: !layout.available, dot: false }];
        if self.label {
            parts.push(if layout.available {
                Part::DimLabel { text: keyboard::short_label(&layout.current) }
            } else {
                Part::Meta { text: "NO LAYOUT".into() }
            });
        }
        View::new(parts, look.xxs).tooltip(keyboard::tooltip_text(Some(layout)))
    }
}
