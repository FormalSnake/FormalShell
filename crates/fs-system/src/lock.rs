//! The lock surface's two decisions that need no scene: which ink the words on
//! the wallpaper take, and where the keyboard cursor over the now-playing
//! transport goes.

/// What the wallpaper sampler reports: the mean luma on 0..255 (Rec. 601) and
/// whether a sample was taken at all.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stats {
    pub mean: f64,
    pub sampled: bool,
}

/// Ink by contrast against what is actually behind the words: the sampled
/// wallpaper's mean luma under the surface's black scrim at `scrim_alpha`, or,
/// with no wallpaper sampled, the flat colour the surface fills with instead
/// (`fallback_luma`, the same 0..255). "light" is white words, "dark" black
/// ones, whichever has the larger WCAG contrast ratio against that backdrop;
/// the two cross at a relative luminance of sqrt(0.0525) - 0.05, which is ~118
/// on 0..255. The theme's own foreground is never consulted: a light theme's
/// near-black foreground over a dark wallpaper is exactly the case this exists
/// for.
pub fn backdrop_luma(stats: Option<&Stats>, scrim_alpha: f64, fallback_luma: f64) -> f64 {
    match stats {
        Some(s) if s.sampled => s.mean * (1.0 - 0.0_f64.max(1.0_f64.min(scrim_alpha))),
        _ => fallback_luma,
    }
}

/// sRGB's transfer function, 0..255 in, relative luminance 0..1 out.
pub fn linear(value: f64) -> f64 {
    let c = 0.0_f64.max(255.0_f64.min(value)) / 255.0;
    if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

pub fn contrast(a: f64, b: f64) -> f64 {
    let hi = a.max(b);
    let lo = a.min(b);
    (hi + 0.05) / (lo + 0.05)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ink {
    Light,
    Dark,
}

impl Ink {
    pub fn as_str(self) -> &'static str {
        match self {
            Ink::Light => "light",
            Ink::Dark => "dark",
        }
    }
}

pub fn ink(stats: Option<&Stats>, scrim_alpha: f64, fallback_luma: f64) -> Ink {
    let backdrop = linear(backdrop_luma(stats, scrim_alpha, fallback_luma));
    if contrast(1.0, backdrop) >= contrast(0.0, backdrop) { Ink::Light } else { Ink::Dark }
}

/// A colour's Rec. 601 luma on 0..255, off 0..1 channels, for the fallback
/// above.
pub fn luma_of(r: f64, g: f64, b: f64) -> f64 {
    255.0 * (0.299 * r + 0.587 * g + 0.114 * b)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportKey {
    Tab,
    Backtab,
    Left,
    Right,
    Enter,
    Escape,
    Modifier,
    Other,
}

impl TransportKey {
    /// Anything that is not one of the named keys is a typed character.
    pub fn parse(key: &str) -> TransportKey {
        match key {
            "tab" => TransportKey::Tab,
            "backtab" => TransportKey::Backtab,
            "left" => TransportKey::Left,
            "right" => TransportKey::Right,
            "enter" => TransportKey::Enter,
            "escape" => TransportKey::Escape,
            "modifier" => TransportKey::Modifier,
            _ => TransportKey::Other,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransportState {
    pub index: i32,
    pub taken: bool,
    pub press: bool,
}

/// The transport cursor. The password field keeps keyboard focus for the whole
/// time the surface is up and every key still reaches it first; this only
/// decides which of those keys the transport takes instead. `index` is -1 while
/// the cursor is off (the field's own state) and a button index while it is on;
/// `count` is how many buttons there are, 0 while the block is hidden.
///
/// Tab and Backtab walk the buttons and fall off either end back to the field.
/// While a button holds the cursor, Left and Right step along the row (clamped),
/// Enter presses it and Escape hands the cursor back. Anything else hands it
/// back too and is NOT taken, so the first character of a password still lands
/// in the field. Modifier presses on their own change nothing: Shift is half of
/// Backtab.
///
/// Returns the next index, whether the key was taken, and whether it pressed
/// the button under the cursor.
pub fn transport_key(index: i32, count: i32, key: TransportKey) -> TransportState {
    let mut out = TransportState { index, taken: false, press: false };
    if count <= 0 {
        out.index = -1;
        return out;
    }
    if index >= count {
        out.index = count - 1;
    }
    match key {
        TransportKey::Modifier => return out,
        TransportKey::Tab => {
            out.index = if out.index + 1 >= count { -1 } else { out.index + 1 };
            out.taken = true;
            return out;
        }
        TransportKey::Backtab => {
            out.index = if out.index < 0 { count - 1 } else { out.index - 1 };
            out.taken = true;
            return out;
        }
        _ => {}
    }
    if out.index < 0 {
        return out;
    }
    match key {
        TransportKey::Left => {
            out.index = 0.max(out.index - 1);
            out.taken = true;
        }
        TransportKey::Right => {
            out.index = (count - 1).min(out.index + 1);
            out.taken = true;
        }
        TransportKey::Enter => {
            out.press = true;
            out.taken = true;
        }
        TransportKey::Escape => {
            out.index = -1;
            out.taken = true;
        }
        _ => out.index = -1,
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stats(mean: f64) -> Stats {
        Stats { mean, sampled: true }
    }

    fn close(a: f64, b: f64) {
        assert!((a - b).abs() < 0.001, "{a} vs {b}");
    }

    fn ink_of(s: Option<&Stats>, alpha: f64, fallback: f64) -> &'static str {
        ink(s, alpha, fallback).as_str()
    }

    // --- Ink ---

    #[test]
    fn a_dark_wallpaper_takes_light_ink() {
        assert_eq!(ink_of(Some(&stats(30.0)), 0.5, 0.0), "light");
        assert_eq!(ink_of(Some(&stats(30.0)), 0.0, 0.0), "light");
    }

    /// The scrim is what the words actually sit on: a white field under black at
    /// 0.5 is mid grey, where black words out-contrast white ones.
    #[test]
    fn a_white_wallpaper_under_the_scrim_takes_dark_ink() {
        assert_eq!(ink_of(Some(&stats(255.0)), 0.5, 0.0), "dark");
    }

    /// A bright but not white field under the same scrim lands below the
    /// crossover (~118 after the scrim) and keeps light ink.
    #[test]
    fn the_scrim_moves_the_crossover() {
        assert_eq!(ink_of(Some(&stats(230.0)), 0.5, 0.0), "light");
        assert_eq!(ink_of(Some(&stats(230.0)), 0.0, 0.0), "dark");
    }

    #[test]
    fn the_crossover_sits_near_118() {
        assert_eq!(ink_of(Some(&stats(112.0)), 0.0, 0.0), "light");
        assert_eq!(ink_of(Some(&stats(124.0)), 0.0, 0.0), "dark");
    }

    /// Nothing sampled reads the fallback, which is the flat colour the surface
    /// fills with instead.
    #[test]
    fn an_unsampled_wallpaper_reads_the_fallback() {
        let none = Stats { mean: 0.0, sampled: false };
        assert_eq!(ink_of(Some(&none), 0.5, 250.0), "dark");
        assert_eq!(ink_of(Some(&none), 0.5, 10.0), "light");
        assert_eq!(ink_of(None, 0.5, 250.0), "dark");
        assert_eq!(backdrop_luma(Some(&none), 0.5, 42.0), 42.0);
    }

    #[test]
    fn backdrop_luma_is_the_mean_under_black_at_the_scrim() {
        close(backdrop_luma(Some(&stats(200.0)), 0.5, 0.0), 100.0);
        close(backdrop_luma(Some(&stats(200.0)), 0.0, 0.0), 200.0);
    }

    #[test]
    fn luma_of_a_colour() {
        close(luma_of(1.0, 1.0, 1.0), 255.0);
        close(luma_of(0.0, 0.0, 0.0), 0.0);
    }

    // --- The transport cursor ---

    fn key(index: i32, count: i32, k: &str) -> TransportState {
        transport_key(index, count, TransportKey::parse(k))
    }

    #[test]
    fn tab_walks_the_buttons_and_falls_back_to_the_field() {
        let s = key(-1, 3, "tab");
        assert_eq!(s.index, 0);
        assert!(s.taken);
        let s = key(2, 3, "tab");
        assert_eq!(s.index, -1);
        assert!(s.taken);
    }

    #[test]
    fn backtab_walks_back_from_the_field_to_the_last_button() {
        assert_eq!(key(-1, 3, "backtab").index, 2);
        assert_eq!(key(0, 3, "backtab").index, -1);
    }

    /// With the cursor off every other key is the field's.
    #[test]
    fn the_field_keeps_its_keys_while_the_cursor_is_off() {
        for k in ["left", "right", "enter", "escape", "other"] {
            let s = key(-1, 3, k);
            assert_eq!(s.index, -1, "{k}");
            assert!(!s.taken, "{k}");
            assert!(!s.press, "{k}");
        }
    }

    #[test]
    fn arrows_step_clamped_while_the_cursor_is_on() {
        assert_eq!(key(0, 3, "left").index, 0);
        assert_eq!(key(0, 3, "right").index, 1);
        assert_eq!(key(2, 3, "right").index, 2);
        assert!(key(1, 3, "left").taken);
    }

    #[test]
    fn enter_presses_the_button_under_the_cursor() {
        let s = key(1, 3, "enter");
        assert_eq!(s.index, 1);
        assert!(s.press);
        assert!(s.taken);
    }

    #[test]
    fn escape_hands_the_cursor_back() {
        let s = key(1, 3, "escape");
        assert_eq!(s.index, -1);
        assert!(s.taken);
    }

    /// Typing always reaches the password: the character is not taken, and the
    /// cursor goes back to the field with it.
    #[test]
    fn a_typed_character_goes_to_the_field() {
        let s = key(1, 3, "other");
        assert_eq!(s.index, -1);
        assert!(!s.taken);
        assert!(!s.press);
    }

    /// Shift on its own is half of Backtab and must not drop the cursor.
    #[test]
    fn a_modifier_alone_changes_nothing() {
        let s = key(1, 3, "modifier");
        assert_eq!(s.index, 1);
        assert!(!s.taken);
    }

    #[test]
    fn no_buttons_means_no_cursor() {
        let s = key(1, 0, "tab");
        assert_eq!(s.index, -1);
        assert!(!s.taken);
    }
}
