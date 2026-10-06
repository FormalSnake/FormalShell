//! The state surfaces read. Services own their slice's shape and how a
//! diff applies to it; the UI thread is the only writer, through
//! [`Store::apply`].

use crate::services::{clock, config, hyprland, state};

#[derive(Default)]
pub struct Store {
    pub clock: clock::State,
    pub config: config::State,
    pub hyprland: hyprland::State,
    pub state: state::State,
}

/// One service's change, tagged with the slice it applies to.
pub enum Diff {
    Clock(clock::Diff),
    Config(config::Diff),
    Hyprland(hyprland::Diff),
    State(state::Diff),
}

/// The slice a diff changed, for the surfaces that read it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Topic {
    Clock,
    Config,
    Hyprland,
    State,
}

impl Store {
    /// `None` when the diff left the slice as it was, so nothing redraws.
    pub fn apply(&mut self, diff: Diff) -> Option<Topic> {
        match diff {
            Diff::Clock(d) => self.clock.apply(d).then_some(Topic::Clock),
            Diff::Config(d) => self.config.apply(d).then_some(Topic::Config),
            Diff::State(d) => self.state.apply(d).then_some(Topic::State),
            Diff::Hyprland(d) => self.hyprland.apply(d).then_some(Topic::Hyprland),
        }
    }
}
