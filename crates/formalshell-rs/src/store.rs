//! The state surfaces read. Services own their slice's shape and how a
//! diff applies to it; the UI thread is the only writer, through
//! [`Store::apply`].

use crate::services::{
    appicon, barpaint, caffeinate, clock, commands, config, devices, herdr, hyprland, info, media, plugins, recording, state,
    theme, tray, visualizer, wallpaper,
};

#[derive(Default)]
pub struct Store {
    pub clock: clock::State,
    pub config: config::State,
    pub hyprland: hyprland::State,
    pub state: state::State,
    pub theme: theme::State,
    pub media: media::State,
    pub visualizer: visualizer::State,
    pub devices: devices::State,
    pub commands: commands::State,
    pub bar_paint: barpaint::State,
    pub wallpaper: wallpaper::State,
    pub tray: tray::State,
    pub herdr: herdr::State,
    pub appicon: appicon::State,
    pub info: info::State,
    pub caffeinate: caffeinate::State,
    pub plugins: plugins::State,
    pub recording: recording::State,
}

/// One service's change, tagged with the slice it applies to.
pub enum Diff {
    Clock(clock::Diff),
    Config(config::Diff),
    Hyprland(hyprland::Diff),
    State(state::Diff),
    Theme(theme::Diff),
    Media(media::Diff),
    Visualizer(visualizer::Diff),
    Devices(devices::Diff),
    Commands(commands::Diff),
    BarPaint(barpaint::Diff),
    Wallpaper(wallpaper::Diff),
    Tray(tray::Diff),
    Herdr(herdr::Diff),
    AppIcon(appicon::Diff),
    Info(info::Diff),
    Caffeinate(caffeinate::Diff),
    Plugins(plugins::Diff),
    #[allow(dead_code)]
    Recording(recording::Diff),
}

/// The slice a diff changed, for the surfaces that read it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Topic {
    Clock,
    Config,
    Hyprland,
    State,
    Theme,
    Media,
    Visualizer,
    Devices,
    Commands,
    BarPaint,
    Wallpaper,
    Tray,
    Herdr,
    AppIcon,
    Info,
    Caffeinate,
    /// The plugin list changed: the layout resolves again.
    Plugins,
    /// What a plugin shows changed.
    PluginOutput,
    Recording,
}

impl Store {
    /// `None` when the diff left the slice as it was, so nothing redraws.
    pub fn apply(&mut self, diff: Diff) -> Option<Topic> {
        match diff {
            Diff::Clock(d) => self.clock.apply(d).then_some(Topic::Clock),
            Diff::Config(d) => self.config.apply(d).then_some(Topic::Config),
            Diff::State(d) => self.state.apply(d).then_some(Topic::State),
            Diff::Hyprland(d) => self.hyprland.apply(d).then_some(Topic::Hyprland),
            Diff::Theme(d) => self.theme.apply(d).then_some(Topic::Theme),
            Diff::Media(d) => self.media.apply(d).then_some(Topic::Media),
            Diff::Visualizer(d) => self.visualizer.apply(d).then_some(Topic::Visualizer),
            Diff::Devices(d) => self.devices.apply(d).then_some(Topic::Devices),
            Diff::Commands(d) => self.commands.apply(d).then_some(Topic::Commands),
            Diff::BarPaint(d) => self.bar_paint.apply(d).then_some(Topic::BarPaint),
            Diff::Wallpaper(d) => self.wallpaper.apply(d).then_some(Topic::Wallpaper),
            Diff::Tray(d) => self.tray.apply(d).then_some(Topic::Tray),
            Diff::Herdr(d) => self.herdr.apply(d).then_some(Topic::Herdr),
            Diff::AppIcon(d) => self.appicon.apply(d).then_some(Topic::AppIcon),
            Diff::Info(d) => self.info.apply(d).then_some(Topic::Info),
            Diff::Plugins(d) => self.plugins.apply(d).map(|c| match c {
                plugins::Change::List => Topic::Plugins,
                plugins::Change::Output => Topic::PluginOutput,
            }),
            Diff::Recording(d) => self.recording.apply(d).then_some(Topic::Recording),
            Diff::Caffeinate(d) => self.caffeinate.apply(d).then_some(Topic::Caffeinate),
        }
    }
}
