//! Each surface reads its slices of the store; [`changed`] routes a store
//! change to the surfaces that read that slice.

pub mod bar;
pub mod card;
pub mod panel;
pub mod shoulders;
pub mod switcher;
pub mod tray_menu;
pub mod tooltip;

use crate::services::theme;
use crate::store::Topic;
use crate::wayland::{App, theme_inputs};

pub fn changed(app: &mut App, topic: Topic) {
    app.switcher_changed(topic);
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
        Topic::Plugins => app.apply_config(),
        Topic::Theme => app.set_bar_theme(),
        Topic::Tray => {
            app.tray_changed();
            app.refresh_bar(Some(topic));
        }
        _ => app.refresh_bar(Some(topic)),
    }
}
