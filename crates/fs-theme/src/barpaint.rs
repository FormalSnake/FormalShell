//! wingpanel's adaptive panel as pure functions: the statistics of the
//! wallpaper band under the bar, and the paint they decide. Transcribed from
//! elementary's GPL sources (`BackgroundManager.vala` for the decision, gala's
//! `Background.get_color_information` for the three numbers); the recipe is
//! read, nothing is ported.
//!
//! The constants are the decision's own and live here rather than in a theme
//! table: a table describes how a band is painted, this decides which of its
//! paints the wallpaper asks for. Only the wallpaper's own pixels are ever
//! sampled, never the screen, so a window under the band is not seen, which
//! is wingpanel's compromise and why it goes solid once one covers the
//! output.

/// Rec. 601 luma, the weighting gala reads a wallpaper's brightness with,
/// on 0..255.
const LUMA_R: f64 = 0.299;
const LUMA_G: f64 = 0.587;
const LUMA_B: f64 = 0.114;

/// A band is bright above the mean threshold, busy above either of the next
/// two, and the sigma rule catches a band whose mean is dark but whose spread
/// puts a twentieth of it in the light: 1.645 is the 95th percentile of a
/// normal distribution.
pub const LUMA_THRESHOLD: f64 = 180.0;
pub const STD_THRESHOLD: f64 = 45.0;
pub const ACUTANCE_THRESHOLD: f64 = 8.0;
pub const SIGMA: f64 = 1.645;

/// How wide the whole wallpaper is sampled, the band's rows taken out of
/// that. The mean and spread are scale-free and the acutance keeps its edges
/// as long as the downscale is nearest-neighbour.
pub const SAMPLE_WIDTH: u32 = 240;

/// What `bar.paint` may say. `auto` is wingpanel's rule; `transparent` is
/// that rule with the busy branch taken out; the other five pin one paint.
pub const PINS: [&str; 7] = [
    "auto",
    "transparent",
    "light",
    "dark",
    "translucentLight",
    "translucentDark",
    "maximized",
];

/// The five paints a band can wear. The strings are the theme state names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Paint {
    Light,
    Dark,
    TranslucentLight,
    TranslucentDark,
    Maximized,
}

impl Paint {
    pub fn as_str(self) -> &'static str {
        match self {
            Paint::Light => "light",
            Paint::Dark => "dark",
            Paint::TranslucentLight => "translucentLight",
            Paint::TranslucentDark => "translucentDark",
            Paint::Maximized => "maximized",
        }
    }
}

/// A resolved `bar.paint` value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pin {
    Auto,
    Transparent,
    Paint(Paint),
}

impl Pin {
    pub fn as_str(self) -> &'static str {
        match self {
            Pin::Auto => "auto",
            Pin::Transparent => "transparent",
            Pin::Paint(p) => p.as_str(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stats {
    pub mean: f64,
    pub std: f64,
    pub acutance: f64,
    pub sampled: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// JS `Math.round`: halves go up, also for negatives.
fn js_round(x: f64) -> f64 {
    let floor = x.floor();
    if x - floor >= 0.5 { floor + 1.0 } else { floor }
}

/// The three numbers, off one RGBA run (a Canvas `getImageData().data`) of
/// `width` by `height` samples. `acutance` is the mean absolute luminance
/// difference between horizontally adjacent samples, so a flat field reads 0
/// and a checker reads the contrast between its squares. A run shorter than
/// the grid needs reads as unsampled.
pub fn stats(data: &[u8], width: usize, height: usize) -> Stats {
    let count = width * height;
    if count == 0 || data.len() < count * 4 {
        return Stats {
            mean: 0.0,
            std: 0.0,
            acutance: 0.0,
            sampled: false,
        };
    }

    let mut sum = 0.0;
    let mut square = 0.0;
    let mut edge = 0.0;
    let mut edges = 0u64;
    for y in 0..height {
        let mut prev = -1.0;
        for x in 0..width {
            let i = (y * width + x) * 4;
            let luma =
                LUMA_R * data[i] as f64 + LUMA_G * data[i + 1] as f64 + LUMA_B * data[i + 2] as f64;
            sum += luma;
            square += luma * luma;
            if prev >= 0.0 {
                edge += (luma - prev).abs();
                edges += 1;
            }
            prev = luma;
        }
    }
    let mean = sum / count as f64;
    // Clamped at 0: the variance of a flat field is a difference of two
    // large sums and lands a hair below zero in floating point.
    let variance = (square / count as f64 - mean * mean).max(0.0);
    Stats {
        mean,
        std: variance.sqrt(),
        acutance: if edges > 0 { edge / edges as f64 } else { 0.0 },
        sampled: true,
    }
}

/// Whether the band is too busy to read ink off directly, which is what makes
/// wingpanel draw a translucent panel at all.
pub fn busy(s: Option<&Stats>) -> bool {
    let Some(s) = s.filter(|s| s.sampled) else {
        return false;
    };
    s.std > STD_THRESHOLD
        || s.acutance > ACUTANCE_THRESHOLD
        || (s.mean < LUMA_THRESHOLD && s.mean + SIGMA * s.std > LUMA_THRESHOLD)
}

/// An unknown value is a typo rather than a request, and reads as the rule.
pub fn pin(value: Option<&str>) -> Pin {
    match value {
        Some("transparent") => Pin::Transparent,
        Some("light") => Pin::Paint(Paint::Light),
        Some("dark") => Pin::Paint(Paint::Dark),
        Some("translucentLight") => Pin::Paint(Paint::TranslucentLight),
        Some("translucentDark") => Pin::Paint(Paint::TranslucentDark),
        Some("maximized") => Pin::Paint(Paint::Maximized),
        _ => Pin::Auto,
    }
}

/// The paint. A pinned paint is the answer whatever is under the band,
/// including a window over it. Under the two rules a window covering the
/// output wins over everything the wallpaper says. With no wallpaper set the
/// honest answer is the bare band with light ink.
pub fn decide(s: Option<&Stats>, mode: &str, fullscreen: bool, pinned: Option<&str>) -> Paint {
    let p = pin(pinned);
    if let Pin::Paint(paint) = p {
        return paint;
    }
    if fullscreen {
        return Paint::Maximized;
    }
    let Some(s) = s.filter(|s| s.sampled) else {
        return Paint::Light;
    };
    if p == Pin::Auto && busy(Some(s)) {
        return if mode == "light" {
            Paint::TranslucentLight
        } else {
            Paint::TranslucentDark
        };
    }
    if s.mean > LUMA_THRESHOLD {
        Paint::Dark
    } else {
        Paint::Light
    }
}

/// What one output's band wears, given the reading taken on the main display.
/// The wallpaper is one picture across the session, so the reading is shared
/// and the only per-output term left is a window covering that output.
pub fn decide_for(
    s: Option<&Stats>,
    mode: &str,
    fullscreen_outputs: Option<&[&str]>,
    name: &str,
    pinned: Option<&str>,
) -> Paint {
    let covered = fullscreen_outputs.is_some_and(|outputs| outputs.contains(&name));
    decide(s, mode, covered, pinned)
}

/// The band's rect inside a sample of the whole wallpaper: the bar's own edge
/// and thickness against the output's size, scaled and clamped so a band
/// thinner than one sample row still has a row to read.
pub fn band_rect(
    edge: &str,
    thickness: f64,
    screen_width: f64,
    screen_height: f64,
    sample_width: f64,
    sample_height: f64,
) -> Rect {
    let across = js_round(thickness / screen_height.max(1.0) * sample_height).max(1.0);
    let down = js_round(thickness / screen_width.max(1.0) * sample_width).max(1.0);
    match edge {
        "bottom" => Rect {
            x: 0.0,
            y: (sample_height - across).max(0.0),
            width: sample_width,
            height: across,
        },
        "left" => Rect {
            x: 0.0,
            y: 0.0,
            width: down,
            height: sample_height,
        },
        "right" => Rect {
            x: (sample_width - down).max(0.0),
            y: 0.0,
            width: down,
            height: sample_height,
        },
        _ => Rect {
            x: 0.0,
            y: 0.0,
            width: sample_width,
            height: across,
        },
    }
}

/// Any other rect of the output inside the same sample, for a reader that is
/// not a band (the lock clock and the now-playing block under it). Scaled the
/// way `band_rect` scales, clamped inside the sample, and never thinner than
/// one sample on either axis.
#[allow(clippy::too_many_arguments)]
pub fn region_rect(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    screen_width: f64,
    screen_height: f64,
    sample_width: f64,
    sample_height: f64,
) -> Rect {
    let sx = sample_width / screen_width.max(1.0);
    let sy = sample_height / screen_height.max(1.0);
    let left = (x * sx).floor().min(sample_width - 1.0).max(0.0);
    let top = (y * sy).floor().min(sample_height - 1.0).max(0.0);
    let right = ((x + width) * sx).ceil().min(sample_width).max(left + 1.0);
    let bottom = ((y + height) * sy).ceil().min(sample_height).max(top + 1.0);
    Rect {
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn st(mean: f64, std: f64, acutance: f64) -> Stats {
        Stats {
            mean,
            std,
            acutance,
            sampled: true,
        }
    }

    fn pixels(values: &[u8]) -> Vec<u8> {
        values.iter().flat_map(|&v| [v, v, v, 255]).collect()
    }

    fn near(a: f64, b: f64) -> bool {
        (a - b).abs() < 0.001
    }

    #[test]
    fn a_flat_field_has_its_own_mean_and_no_spread_or_edges() {
        let s = stats(&pixels(&[200, 200, 200, 200]), 4, 1);
        assert!(s.sampled);
        assert!(near(s.mean, 200.0));
        assert!(near(s.std, 0.0));
        assert!(near(s.acutance, 0.0));
    }

    #[test]
    fn a_checker_row_carries_the_spread_and_the_edges() {
        let s = stats(&pixels(&[0, 255, 0, 255]), 4, 1);
        assert!(near(s.mean, 127.5));
        assert!(near(s.std, 127.5));
        assert!(near(s.acutance, 255.0));
    }

    #[test]
    fn acutance_reads_along_a_row_and_not_down_a_column() {
        let s = stats(&pixels(&[0, 0, 255, 255]), 2, 2);
        assert!(near(s.mean, 127.5));
        assert!(near(s.acutance, 0.0));
    }

    #[test]
    fn no_samples_is_not_a_reading() {
        let s = stats(&[], 0, 0);
        assert!(!s.sampled);
    }

    #[test]
    fn a_calm_bright_band_takes_dark_ink_on_no_fill() {
        assert_eq!(
            decide(Some(&st(230.0, 0.0, 0.0)), "dark", false, None).as_str(),
            "dark"
        );
    }

    #[test]
    fn a_calm_dark_band_takes_light_ink_on_no_fill() {
        assert_eq!(
            decide(Some(&st(30.0, 0.0, 0.0)), "dark", false, None).as_str(),
            "light"
        );
    }

    #[test]
    fn spread_alone_makes_a_band_busy() {
        assert!(!busy(Some(&st(60.0, STD_THRESHOLD, 0.0))));
        assert!(busy(Some(&st(60.0, STD_THRESHOLD + 1.0, 0.0))));
    }

    #[test]
    fn acutance_alone_makes_a_band_busy() {
        assert!(!busy(Some(&st(60.0, 0.0, ACUTANCE_THRESHOLD))));
        assert!(busy(Some(&st(60.0, 0.0, ACUTANCE_THRESHOLD + 1.0))));
    }

    #[test]
    fn the_sigma_rule_catches_a_dark_band_with_bright_parts() {
        let boundary = LUMA_THRESHOLD - SIGMA * 40.0;
        assert!(!busy(Some(&st(boundary - 1.0, 40.0, 0.0))));
        assert!(busy(Some(&st(boundary + 1.0, 40.0, 0.0))));
    }

    #[test]
    fn a_bright_band_is_not_busy_by_the_sigma_rule() {
        assert!(!busy(Some(&st(200.0, 40.0, 0.0))));
        assert_eq!(
            decide(Some(&st(200.0, 40.0, 0.0)), "dark", false, None).as_str(),
            "dark"
        );
    }

    #[test]
    fn the_mode_picks_between_the_two_translucent_paints() {
        let b = st(120.0, 80.0, 0.0);
        assert_eq!(
            decide(Some(&b), "dark", false, None).as_str(),
            "translucentDark"
        );
        assert_eq!(
            decide(Some(&b), "light", false, None).as_str(),
            "translucentLight"
        );
    }

    #[test]
    fn a_window_covering_the_output_wins_over_every_reading() {
        assert_eq!(
            decide(Some(&st(230.0, 0.0, 0.0)), "dark", true, None).as_str(),
            "maximized"
        );
        assert_eq!(
            decide(Some(&st(120.0, 80.0, 0.0)), "light", true, None).as_str(),
            "maximized"
        );
        assert_eq!(decide(None, "dark", true, None).as_str(), "maximized");
    }

    #[test]
    fn nothing_sampled_reads_as_the_bare_band() {
        assert_eq!(decide(None, "dark", false, None).as_str(), "light");
        let unsampled = Stats {
            mean: 0.0,
            std: 0.0,
            acutance: 0.0,
            sampled: false,
        };
        assert_eq!(
            decide(Some(&unsampled), "light", false, None).as_str(),
            "light"
        );
    }

    /// JS also feeds 42, null and undefined; a `&str` option has only `None`
    /// for all three. "constructor" covers the inherited-property case.
    #[test]
    fn an_unknown_pin_reads_as_the_rule() {
        assert_eq!(pin(Some("auto")).as_str(), "auto");
        assert_eq!(pin(Some("transparent")).as_str(), "transparent");
        assert_eq!(pin(Some("translucentDark")).as_str(), "translucentDark");
        assert_eq!(pin(Some("solid")).as_str(), "auto");
        assert_eq!(pin(Some("")).as_str(), "auto");
        assert_eq!(pin(None).as_str(), "auto");
        assert_eq!(pin(Some("constructor")).as_str(), "auto");
        for p in PINS {
            assert_eq!(pin(Some(p)).as_str(), p);
        }
    }

    #[test]
    fn a_pinned_paint_wins_over_the_sample() {
        let b = st(120.0, 80.0, 0.0);
        assert_eq!(
            decide(Some(&b), "dark", false, Some("light")).as_str(),
            "light"
        );
        assert_eq!(
            decide(
                Some(&st(230.0, 0.0, 0.0)),
                "dark",
                false,
                Some("translucentDark")
            )
            .as_str(),
            "translucentDark"
        );
        assert_eq!(
            decide(Some(&b), "dark", true, Some("dark")).as_str(),
            "dark"
        );
        assert_eq!(
            decide(None, "dark", false, Some("maximized")).as_str(),
            "maximized"
        );
    }

    #[test]
    fn auto_samples_the_way_it_always_did() {
        let b = st(120.0, 80.0, 0.0);
        assert_eq!(
            decide(Some(&b), "dark", false, Some("auto")),
            decide(Some(&b), "dark", false, None)
        );
        assert_eq!(
            decide(Some(&b), "light", false, Some("auto")).as_str(),
            "translucentLight"
        );
        assert_eq!(
            decide(Some(&st(230.0, 0.0, 0.0)), "dark", false, Some("auto")).as_str(),
            "dark"
        );
        assert_eq!(
            decide(Some(&st(30.0, 0.0, 0.0)), "dark", false, Some("auto")).as_str(),
            "light"
        );
        assert_eq!(
            decide(Some(&st(30.0, 0.0, 0.0)), "dark", true, Some("auto")).as_str(),
            "maximized"
        );
        assert_eq!(
            decide(Some(&b), "dark", false, Some("solid")).as_str(),
            "translucentDark"
        );
    }

    #[test]
    fn transparent_drops_the_fill_and_keeps_the_ink_adaptive() {
        let t = Some("transparent");
        assert_eq!(
            decide(Some(&st(120.0, 80.0, 0.0)), "dark", false, t).as_str(),
            "light"
        );
        assert_eq!(
            decide(Some(&st(230.0, 80.0, 0.0)), "dark", false, t).as_str(),
            "dark"
        );
        assert_eq!(
            decide(Some(&st(200.0, 80.0, 20.0)), "light", false, t).as_str(),
            "dark"
        );
        assert_eq!(
            decide(Some(&st(30.0, 0.0, 0.0)), "dark", false, t).as_str(),
            "light"
        );
        assert_eq!(decide(None, "dark", false, t).as_str(), "light");
        assert_eq!(
            decide(Some(&st(230.0, 0.0, 0.0)), "dark", true, t).as_str(),
            "maximized"
        );
    }

    #[test]
    fn every_output_wears_the_one_reading() {
        let bright = st(230.0, 0.0, 0.0);
        let a = Some("auto");
        assert_eq!(
            decide_for(Some(&bright), "dark", Some(&[]), "HDMI-A-1", a).as_str(),
            "dark"
        );
        assert_eq!(
            decide_for(Some(&bright), "dark", Some(&[]), "eDP-1", a).as_str(),
            "dark"
        );

        let b = st(120.0, 80.0, 0.0);
        assert_eq!(
            decide_for(Some(&b), "dark", Some(&[]), "HDMI-A-1", a).as_str(),
            "translucentDark"
        );
        assert_eq!(
            decide_for(Some(&b), "dark", Some(&[]), "eDP-1", a).as_str(),
            "translucentDark"
        );
    }

    #[test]
    fn a_covered_output_blackens_its_own_band_alone() {
        let bright = st(230.0, 0.0, 0.0);
        let a = Some("auto");
        assert_eq!(
            decide_for(Some(&bright), "dark", Some(&["eDP-1"]), "eDP-1", a).as_str(),
            "maximized"
        );
        assert_eq!(
            decide_for(Some(&bright), "dark", Some(&["eDP-1"]), "HDMI-A-1", a).as_str(),
            "dark"
        );
    }

    #[test]
    fn no_fullscreen_set_is_no_window() {
        let bright = st(230.0, 0.0, 0.0);
        let a = Some("auto");
        assert_eq!(
            decide_for(Some(&bright), "dark", Some(&[]), "eDP-1", a).as_str(),
            "dark"
        );
        assert_eq!(
            decide_for(Some(&bright), "dark", None, "eDP-1", a).as_str(),
            "dark"
        );
    }

    #[test]
    fn the_band_rect_follows_the_bar_edge() {
        let top = band_rect("top", 40.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(top.x, 0.0);
        assert_eq!(top.y, 0.0);
        assert_eq!(top.width, 240.0);
        assert_eq!(top.height, 5.0);

        let bottom = band_rect("bottom", 40.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(bottom.y, 130.0);
        assert_eq!(bottom.height, 5.0);

        let right = band_rect("right", 40.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(right.width, 5.0);
        assert_eq!(right.height, 135.0);
        assert_eq!(right.x, 235.0);

        let left = band_rect("left", 40.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(left.x, 0.0);
        assert_eq!(left.width, 5.0);
    }

    #[test]
    fn the_band_rect_never_collapses() {
        let band = band_rect("top", 1.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(band.height, 1.0);
    }

    #[test]
    fn a_region_rect_scales_into_the_sample() {
        let r = region_rect(760.0, 440.0, 400.0, 200.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(r.x, 95.0);
        assert_eq!(r.y, 55.0);
        assert_eq!(r.width, 50.0);
        assert_eq!(r.height, 25.0);
    }

    #[test]
    fn a_region_rect_is_clamped_and_never_empty() {
        let edge = region_rect(1900.0, 1070.0, 400.0, 400.0, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(edge.x + edge.width, 240.0);
        assert_eq!(edge.y + edge.height, 135.0);
        let speck = region_rect(10.0, 10.0, 0.1, 0.1, 1920.0, 1080.0, 240.0, 135.0);
        assert_eq!(speck.width, 1.0);
        assert_eq!(speck.height, 1.0);
    }
}
