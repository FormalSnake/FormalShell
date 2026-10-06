//! The metamorphosis look as the bar strip resolves it with no wallpaper
//! palette: `palette.js`'s dark fallback, `presets.js`'s radius and surface
//! alpha, `tokens.js`'s spacing and type at the default scale. Transcribed
//! until R1 moves the theme tables to `themes/*.json`.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba {
    pub const fn hex(rgb: u32) -> Self {
        Self { r: (rgb >> 16) as u8, g: (rgb >> 8) as u8, b: rgb as u8, a: 255 }
    }

    pub fn with_alpha(self, alpha: f32) -> Self {
        Self { a: (alpha.clamp(0.0, 1.0) * 255.0).round() as u8, ..self }
    }
}

pub struct Palette {
    pub card: Rgba,
    pub foreground: Rgba,
    pub muted_foreground: Rgba,
    pub primary: Rgba,
    pub primary_foreground: Rgba,
    pub border: Rgba,
}

pub const DARK: Palette = Palette {
    card: Rgba::hex(0x18181b),
    foreground: Rgba::hex(0xfafafa),
    muted_foreground: Rgba::hex(0xa1a1aa),
    primary: Rgba::hex(0xe4e4e7),
    primary_foreground: Rgba::hex(0x18181b),
    border: Rgba::hex(0x27272a),
};

pub const SURFACE_OPACITY: f32 = 0.85;
pub const RADIUS_BASE: f32 = 10.0;

/// `radiusTokens(base).md`, the corner a bar cell's `active` fill takes.
pub const fn radius_md() -> f32 {
    RADIUS_BASE - 2.0
}

pub const BAR_CELL_HEIGHT: i32 = 28;
pub const BAR_MARGIN: i32 = 6;
pub const SPACE_SM: i32 = 4;
pub const SPACE_MD: i32 = 6;
pub const CONTROL_PADDING_X: i32 = 12;
pub const EDGE_WIDTH: i32 = 1;

pub const FONT_BODY: f32 = 13.0;
pub const WEIGHT_MEDIUM: f32 = 500.0;

/// `stripGeometry`: the cell row plus a `barMargin` band either side.
pub const BAR_THICKNESS: i32 = BAR_CELL_HEIGHT + BAR_MARGIN * 2;

/// `workspaces.persistent`'s default: slots 1..n show even when empty.
pub const PERSISTENT_WORKSPACES: i64 = 5;
