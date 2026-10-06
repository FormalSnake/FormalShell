//! The state surfaces read. Services own their slice's shape and how a
//! diff applies to it; the UI thread is the only writer, through
//! [`Store::apply`].

use crate::services::{clock, hyprland, theme};

#[derive(Default)]
pub struct Store {
    pub clock: clock::State,
    pub hyprland: hyprland::State,
    pub theme: theme::State,
}

/// One service's change, tagged with the slice it applies to.
pub enum Diff {
    Clock(clock::Diff),
    Hyprland(hyprland::Diff),
    Theme(theme::Diff),
}

/// The slice a diff changed, for the surfaces that read it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Topic {
    Clock,
    Hyprland,
    Theme,
}

impl Store {
    /// `None` when the diff left the slice as it was, so nothing redraws.
    pub fn apply(&mut self, diff: Diff) -> Option<Topic> {
        match diff {
            Diff::Clock(d) => self.clock.apply(d).then_some(Topic::Clock),
            Diff::Hyprland(d) => self.hyprland.apply(d).then_some(Topic::Hyprland),
            Diff::Theme(d) => self.theme.apply(d).then_some(Topic::Theme),
        }
    }
}
