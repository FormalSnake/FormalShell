//! A colour as the renderer takes it, and the two pieces of Qt colour
//! arithmetic the chrome tables lean on: `Qt.alpha` and `Qt.tint`.

/// Straight (not premultiplied) RGBA, each channel 0..1.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Rgba {
    pub const TRANSPARENT: Self = Self { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
    pub const BLACK: Self = Self { r: 0.0, g: 0.0, b: 0.0, a: 1.0 };
    pub const WHITE: Self = Self { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };

    pub const fn hex(rgb: u32) -> Self {
        Self {
            r: ((rgb >> 16) & 0xff) as f32 / 255.0,
            g: ((rgb >> 8) & 0xff) as f32 / 255.0,
            b: (rgb & 0xff) as f32 / 255.0,
            a: 1.0,
        }
    }

    /// `#rrggbb` or `#rrggbbaa` (alpha last, the CSS order), or the word
    /// `transparent`. Anything else is `None`.
    pub fn parse(text: &str) -> Option<Self> {
        if text == "transparent" {
            return Some(Self::TRANSPARENT);
        }
        let digits = text.strip_prefix('#')?;
        if !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        let value = u32::from_str_radix(digits, 16).ok()?;
        match digits.len() {
            6 => Some(Self::hex(value)),
            8 => Some(Self { a: (value & 0xff) as f32 / 255.0, ..Self::hex(value >> 8) }),
            _ => None,
        }
    }

    /// `Qt.alpha(c, a)`: the same colour with its alpha replaced, not
    /// multiplied.
    pub fn with_alpha(self, alpha: f32) -> Self {
        Self { a: alpha.clamp(0.0, 1.0), ..self }
    }

    /// `Qt.tint(self, over)`: `over` blended on top by its own alpha, the
    /// result as opaque as the two stacked.
    pub fn tint(self, over: Self) -> Self {
        if over.a >= 1.0 {
            return over;
        }
        if over.a <= 0.0 {
            return self;
        }
        let inv = 1.0 - over.a;
        Self {
            r: over.r * over.a + self.r * inv,
            g: over.g * over.a + self.g * inv,
            b: over.b * over.a + self.b * inv,
            a: over.a + inv * self.a,
        }
    }

    /// Channels as bytes, rounded the way Qt rounds a float channel.
    pub fn to_u8(self) -> [u8; 4] {
        let byte = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
        [byte(self.r), byte(self.g), byte(self.b), byte(self.a)]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hex_and_transparent() {
        assert_eq!(Rgba::parse("#ff0000"), Some(Rgba { r: 1.0, g: 0.0, b: 0.0, a: 1.0 }));
        assert_eq!(Rgba::parse("#00000080").map(|c| c.to_u8()), Some([0, 0, 0, 128]));
        assert_eq!(Rgba::parse("transparent"), Some(Rgba::TRANSPARENT));
        assert_eq!(Rgba::parse("ff0000"), None);
        assert_eq!(Rgba::parse("#ff00"), None);
        assert_eq!(Rgba::parse("#gg0000"), None);
    }

    #[test]
    fn alpha_replaces_rather_than_multiplies() {
        let half = Rgba::hex(0x18181b).with_alpha(0.5);
        assert_eq!(half.with_alpha(0.85).a, 0.85);
    }

    #[test]
    fn tint_blends_over_and_keeps_an_opaque_base_opaque() {
        let base = Rgba::hex(0xe4e4e7);
        let over = Rgba::hex(0x09090b).with_alpha(0.1);
        let out = base.tint(over);
        assert_eq!(out.a, 1.0);
        assert!((out.r - (0x09 as f32 / 255.0 * 0.1 + 0xe4 as f32 / 255.0 * 0.9)).abs() < 1e-6);
        assert_eq!(base.tint(Rgba::WHITE), Rgba::WHITE);
        assert_eq!(base.tint(Rgba::TRANSPARENT), base);
    }
}
