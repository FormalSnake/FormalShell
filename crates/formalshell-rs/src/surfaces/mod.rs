//! Each surface reads its slices of the store; [`changed`] routes a store
//! change to the surfaces that read that slice.

pub mod bar;
pub mod panel;
pub mod shoulders;

use crate::store::Topic;
use crate::wayland::App;

pub fn changed(app: &mut App, topic: Topic) {
    match topic {
        Topic::Clock => app.bar.set_clock(&app.store.clock.text),
        Topic::Hyprland => app.bar.set_workspaces(&app.store.hyprland.slots),
        Topic::Theme => app.bar.set_theme(&app.store.theme.theme),
    }
}
