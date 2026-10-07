//! Each surface reads its slices of the store; [`changed`] routes a store
//! change to the surfaces that read that slice.

pub mod bar;
pub mod card;
pub mod headset;
pub mod launcher;
pub mod lock;
pub mod osd;
pub mod panel;
pub mod popup;
pub mod shoulders;
pub mod switcher;
pub mod tray_menu;
pub mod toasts;
pub mod tooltip;

use crate::services::{lights, theme};
use crate::store::Topic;
use crate::wayland::{App, theme_inputs};

pub fn changed(app: &mut App, topic: Topic) {
    app.lock_changed(topic);
    if matches!(topic, Topic::Hyprland | Topic::State | Topic::Display | Topic::Config) {
        crate::services::display::reconcile(&app.store);
    }
    app.switcher_changed(topic);
    match topic {
        Topic::Menu => app.launcher_store_changed(),
        Topic::Config => {
            app.launcher_inputs();
            let settings = app.store.config.settings().clone();
            if app.store.theme.apply(theme::Diff::Settings(settings)) {
                changed(app, Topic::Theme);
            }
            app.apply_config();
            theme_inputs(app);
            lights_palette(app);
        }
        Topic::State => {
            app.launcher_inputs();
            app.launcher_store_changed();
            theme_inputs(app);
            lights::record(app.store.state.data.lights.clone());
            app.refresh_bar(Some(topic));
        }
        Topic::Plugins => app.apply_config(),
        Topic::Theme => {
            app.set_bar_theme();
            lights_palette(app);
        }
        Topic::Devices => {
            app.osd_audio();
            app.headset_devices();
            app.launcher_devices();
            app.refresh_bar(Some(topic));
        }
        Topic::Tray => {
            app.launcher_tray();
            app.tray_changed();
            app.refresh_bar(Some(topic));
        }
        Topic::Notifications => {
            app.toasts_changed();
            app.refresh_bar(Some(topic));
        }
        Topic::Media => {
            app.launcher_devices();
            app.refresh_bar(Some(topic));
        }
        _ => app.refresh_bar(Some(topic)),
    }
}

/// The theme's primary as the keyboard lights' wallpaper colour.
fn lights_palette(app: &App) {
    let c = app.store.theme.theme.colors.get("primary");
    lights::palette(fs_system::lights::hex_from_rgb(f64::from(c.r) * 255.0, f64::from(c.g) * 255.0, f64::from(c.b) * 255.0));
}
