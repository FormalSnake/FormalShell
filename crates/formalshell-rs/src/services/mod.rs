//! One module per service. Each owns a `State` slice of the
//! [`Store`](crate::store::Store), a `Diff` that applies to it, and an
//! async task on the service thread that publishes those diffs.

pub mod airplay;
pub mod ams;
pub mod appicon;
pub mod barpaint;
pub mod caffeinate;
pub mod clock;
pub mod commands;
pub mod config;
pub mod devices;
pub mod display;
pub mod herdr;
pub mod hyprland;
pub mod icons;
pub mod media;
pub mod menu;
pub mod notifications;
pub mod overnight;
pub mod info;
pub mod plugins;
pub mod proc;
pub mod radio;
pub mod recording;
pub mod state;
mod watch;
pub mod theme;
pub mod tray;
pub mod visualizer;
pub mod wallpaper;
pub mod wants;

use crate::runtime::Ctx;

pub fn start(ctx: &Ctx) {
    ctx.spawn(clock::run(ctx.clone()));
    ctx.spawn(config::run(ctx.clone()));
    ctx.spawn(state::run(ctx.clone()));
    ctx.spawn(hyprland::run(ctx.clone()));
    ctx.spawn(theme::watch(ctx.clone()));
    theme::start(ctx);
    ctx.spawn(media::run(ctx.clone()));
    ctx.spawn(radio::run(ctx.clone()));
    ctx.spawn(airplay::run(ctx.clone()));
    ctx.spawn(ams::run(ctx.clone()));
    ctx.spawn(visualizer::run(ctx.clone()));
    ctx.spawn(commands::run(ctx.clone()));
    ctx.spawn(barpaint::run(ctx.clone()));
    ctx.spawn(wallpaper::run(ctx.clone()));
    ctx.spawn(herdr::run(ctx.clone()));
    ctx.spawn(appicon::run(ctx.clone()));
    ctx.spawn(wants::run(ctx.clone()));
    ctx.spawn(plugins::run(ctx.clone()));
    devices::start(ctx);
    display::start(ctx);
    ctx.spawn(tray::run(ctx.clone()));
    ctx.spawn(menu::run(ctx.clone()));
    ctx.spawn(notifications::run(ctx.clone()));
}
