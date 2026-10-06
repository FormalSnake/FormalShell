//! One module per service. Each owns a `State` slice of the
//! [`Store`](crate::store::Store), a `Diff` that applies to it, and an
//! async task on the service thread that publishes those diffs.

pub mod clock;
pub mod hyprland;
pub mod theme;

use crate::runtime::Ctx;

pub fn start(ctx: &Ctx) {
    ctx.spawn(clock::run(ctx.clone()));
    ctx.spawn(hyprland::run(ctx.clone()));
    ctx.spawn(theme::watch(ctx.clone()));
}
