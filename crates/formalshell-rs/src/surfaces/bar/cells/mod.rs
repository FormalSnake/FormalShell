//! Every bar cell, one module each, and the one place a `bar.layout` entry
//! becomes a cell. Adding a cell is a module here implementing
//! [`Cell`](super::cell::Cell) and one arm in [`build`].
//!
//! The builtins not yet ported draw nothing ([`absent::Absent`]): no
//! stand-in readout, so the strip never shows a value nothing measured.

mod absent;
mod active_window;
mod audio;
mod bell;
mod bluetooth;
mod chevron;
mod clock;
mod command;
mod github;
mod indicators;
mod iphone;
mod keyboard_layout;
mod launcher;
mod monitor;
mod network;
mod now_playing;
mod plugin;
mod system_update;
mod tailscale;
mod usage;
mod weather;
pub mod workspaces;

use fs_chrome::bar::layout::{Builtin, Entry, EntryKind};

use super::cell::Cell;

pub fn build(entry: &Entry, region_entries: &[Entry]) -> Box<dyn Cell> {
    match &entry.kind {
        EntryKind::Builtin(b) => match b {
            Builtin::Launcher => Box::new(launcher::Launcher::default()),
            Builtin::Workspaces => Box::new(workspaces::Workspaces::default()),
            Builtin::ActiveWindow => Box::new(active_window::ActiveWindow::default()),
            Builtin::Clock => Box::new(clock::Clock::default()),
            Builtin::NowPlaying => Box::new(now_playing::NowPlaying::default()),
            Builtin::Audio => Box::new(audio::Audio::default()),
            Builtin::Network => Box::new(network::Network::default()),
            Builtin::Bluetooth => Box::new(bluetooth::Bluetooth::default()),
            Builtin::Weather => Box::new(weather::Weather::default()),
            Builtin::Github => Box::new(github::Github::default()),
            Builtin::Usage => Box::new(usage::Usage::default()),
            Builtin::SystemUpdate => Box::new(system_update::SystemUpdate::default()),
            Builtin::Tailscale => Box::new(tailscale::Tailscale::default()),
            Builtin::KeyboardLayout => Box::new(keyboard_layout::KeyboardLayout::default()),
            Builtin::Monitor => Box::new(monitor::Monitor::default()),
            Builtin::Indicators => Box::new(indicators::Indicators::default()),
            Builtin::Iphone => Box::new(iphone::Iphone::default()),
            Builtin::Bell => Box::new(bell::Bell::default()),
            Builtin::Chevron => Box::new(chevron::Chevron::new(entry.region, region_entries)),
            _ => Box::new(absent::Absent),
        },
        EntryKind::Module { id, module } => match module.get("type").and_then(|t| t.as_str()) {
            Some("command") => Box::new(command::Command::new(id)),
            _ => Box::new(command::Command::qml(id)),
        },
        EntryKind::Plugin { id, .. } => Box::new(plugin::Plugin::new(id)),
    }
}
