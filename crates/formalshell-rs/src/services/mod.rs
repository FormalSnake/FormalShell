//! One module per service. Each owns a `State` slice of the
//! [`Store`](crate::store::Store), a `Diff` that applies to it, and an
//! async task on the service thread that publishes those diffs.

pub mod appicon;
pub mod barpaint;
pub mod clock;
pub mod commands;
pub mod config;
pub mod devices;
pub mod herdr;
pub mod hyprland;
pub mod media;
pub mod state;
mod watch;
pub mod theme;
pub mod wallpaper;

use crate::runtime::Ctx;

pub fn start(ctx: &Ctx) {
    ctx.spawn(clock::run(ctx.clone()));
    ctx.spawn(config::run(ctx.clone()));
    ctx.spawn(state::run(ctx.clone()));
    ctx.spawn(hyprland::run(ctx.clone()));
    ctx.spawn(theme::watch(ctx.clone()));
    theme::start(ctx);
    ctx.spawn(media::run(ctx.clone()));
    ctx.spawn(commands::run(ctx.clone()));
    ctx.spawn(barpaint::run(ctx.clone()));
    ctx.spawn(wallpaper::run(ctx.clone()));
    ctx.spawn(herdr::run(ctx.clone()));
    ctx.spawn(appicon::run(ctx.clone()));
    devices::start(ctx);
}
