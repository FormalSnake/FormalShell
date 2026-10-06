//! One module per service. Each owns a `State` slice of the
//! [`Store`](crate::store::Store), a `Diff` that applies to it, and an
//! async task on the service thread that publishes those diffs.

pub mod clock;
pub mod config;
pub mod hyprland;
pub mod state;
mod watch;
pub mod theme;

use crate::runtime::Ctx;

pub fn start(ctx: &Ctx) {
    ctx.spawn(clock::run(ctx.clone()));
    ctx.spawn(config::run(ctx.clone()));
    ctx.spawn(state::run(ctx.clone()));
    ctx.spawn(hyprland::run(ctx.clone()));
    ctx.spawn(theme::watch(ctx.clone()));
    theme::start(ctx);
}
