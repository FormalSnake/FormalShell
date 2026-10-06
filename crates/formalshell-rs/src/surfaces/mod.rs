//! Each surface reads its slices of the store; [`changed`] routes a store
//! change to the surfaces that read that slice.

pub mod bar;
pub mod card;
pub mod shoulders;

use crate::services::theme;
use crate::store::Topic;
use crate::wayland::{App, theme_inputs};

pub fn changed(app: &mut App, topic: Topic) {
    match topic {
        Topic::Config => {
            let settings = app.store.config.settings().clone();
            if app.store.theme.apply(theme::Diff::Settings(settings)) {
                changed(app, Topic::Theme);
            }
            app.apply_config();
            theme_inputs(app);
        }
        Topic::State => {
            theme_inputs(app);
            app.refresh_bar(Some(topic));
        }
        Topic::Theme => app.set_bar_theme(),
        _ => app.refresh_bar(Some(topic)),
    }
}
