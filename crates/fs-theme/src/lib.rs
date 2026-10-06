//! Theme resolution shared by every surface: the chrome tables in
//! `shell/Theme/themes/*.json`, the tokens, the palette and the pure halves
//! of the matugen pipeline. No IO and no processes; `services::theme` in
//! formalshell-rs runs those.

pub mod barpaint;
pub mod chrome;
pub mod color;
pub mod flexoki;
pub mod gtk;
pub mod matugen;
pub mod palette;
pub mod presets;
pub mod style;
pub mod sun;
pub mod tables;
pub mod theme;
pub mod tokens;
pub mod zenbones;
