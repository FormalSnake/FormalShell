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

/// The sums the three numbers are read off, for one stretch of the band.
/// Two of them add, so a span of the band pools its columns exactly.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Column {
    sum: f64,
    square: f64,
    edge: f64,
    edges: u64,
    count: u64,
}

impl Column {
    fn add(&mut self, other: &Column) {
        self.sum += other.sum;
        self.square += other.square;
        self.edge += other.edge;
        self.edges += other.edges;
        self.count += other.count;
    }

    fn stats(&self) -> Stats {
        if self.count == 0 {
            return Stats {
                mean: 0.0,
                std: 0.0,
                acutance: 0.0,
                sampled: false,
            };
        }
        let count = self.count as f64;
        let mean = self.sum / count;
        // Clamped at 0: the variance of a flat field is a difference of two
        // large sums and lands a hair below zero in floating point.
        let variance = (self.square / count - mean * mean).max(0.0);
        Stats {
            mean,
            std: variance.sqrt(),
            acutance: if self.edges > 0 {
                self.edge / self.edges as f64
            } else {
                0.0
            },
            sampled: true,
        }
    }
}

/// The band's samples kept per column along it, so the whole band and any
/// stretch of it (one cell's) read off the same sums. Empty when the run was
/// shorter than the grid needs.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Profile {
    columns: Vec<Column>,
}

impl Profile {
    /// One RGBA run (a Canvas `getImageData().data`) of `width` by `height`
    /// samples, bucketed along the band: per sample column for a horizontal
    /// band (`along_x`), per row for a vertical one. `acutance` is the mean
    /// absolute luminance difference between horizontally adjacent samples,
    /// so a flat field reads 0 and a checker reads the contrast between its
    /// squares; each difference lands in the bucket of its right-hand sample.
    pub fn read(data: &[u8], width: usize, height: usize, along_x: bool) -> Self {
        let count = width * height;
        if count == 0 || data.len() < count * 4 {
            return Self::default();
        }
        let mut columns = vec![Column::default(); if along_x { width } else { height }];
        for y in 0..height {
            let mut prev = -1.0;
            for x in 0..width {
                let i = (y * width + x) * 4;
                let luma = LUMA_R * data[i] as f64
                    + LUMA_G * data[i + 1] as f64
                    + LUMA_B * data[i + 2] as f64;
                let c = &mut columns[if along_x { x } else { y }];
                c.sum += luma;
                c.square += luma * luma;
                c.count += 1;
                if prev >= 0.0 {
                    c.edge += (luma - prev).abs();
                    c.edges += 1;
                }
                prev = luma;
            }
        }
        Self { columns }
    }

    pub fn len(&self) -> usize {
        self.columns.len()
    }

    pub fn is_empty(&self) -> bool {
        self.columns.is_empty()
    }

    /// The three numbers over the whole band.
    pub fn stats(&self) -> Stats {
        self.span(0.0, 1.0)
    }

    /// The three numbers over the stretch from `from` to `to`, fractions of
    /// the band's length. Never fewer than one column, so a cell thinner than
    /// a sample still reads the column under it.
    pub fn span(&self, from: f64, to: f64) -> Stats {
        let n = self.columns.len();
        if n == 0 {
            return Column::default().stats();
        }
        let (from, to) = (from.min(to), from.max(to));
        let first = ((from * n as f64).floor() as usize).min(n - 1);
        let last = ((to * n as f64).ceil() as usize).clamp(first + 1, n);
        let mut pooled = Column::default();
        for c in &self.columns[first..last] {
            pooled.add(c);
        }
        pooled.stats()
    }
}

/// The three numbers over one RGBA run of `width` by `height` samples
/// (`Profile::read` pooled). A run shorter than the grid needs reads as
/// unsampled.
pub fn stats(data: &[u8], width: usize, height: usize) -> Stats {
    Profile::read(data, width, height, true).stats()
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
    bare(s)
}

/// The bare band's ink off its mean alone: dark words over a bright field,
/// light ones (with their shadow) over anything else.
fn bare(s: &Stats) -> Paint {
    if s.mean > LUMA_THRESHOLD {
        Paint::Dark
    } else {
        Paint::Light
    }
}

/// The ink one cell wears, given the band's paint and the reading of the
/// stretch under that cell. A bare band (no fill of its own, under the
/// rule or `transparent`) lets each cell read its own stretch, which is
/// what keeps the words legible over a wallpaper bright at one end and
/// dark at the other; a band with a fill, a pinned paint and a covered
/// output keep one ink across, since the fill is what the words sit on.
pub fn cell(band: Paint, pinned: Option<&str>, span: &Stats) -> Paint {
    match (pin(pinned), band) {
        (Pin::Auto | Pin::Transparent, Paint::Light | Paint::Dark) if span.sampled => bare(span),
        _ => band,
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
        assert!(Profile::read(&[], 0, 0, true).is_empty());
        assert!(!Profile::default().span(0.0, 1.0).sampled);
    }

    #[test]
    fn a_span_reads_its_own_stretch_of_the_band() {
        // Two rows, black on the left half and white on the right.
        let p = Profile::read(&pixels(&[0, 0, 255, 255, 0, 0, 255, 255]), 4, 2, true);
        assert_eq!(p.len(), 4);
        assert!(near(p.stats().mean, 127.5));
        assert!(near(p.span(0.0, 0.5).mean, 0.0));
        assert!(near(p.span(0.5, 1.0).mean, 255.0));
        assert!(near(p.span(0.0, 0.5).std, 0.0));
        // The edge between the halves lands in the right half's first column.
        assert!(near(p.span(0.5, 0.75).acutance, 255.0));
        assert!(near(p.span(0.0, 0.5).acutance, 0.0));
    }

    #[test]
    fn a_span_is_never_narrower_than_one_column() {
        let p = Profile::read(&pixels(&[0, 255, 0, 255]), 4, 1, true);
        assert!(near(p.span(0.3, 0.3).mean, 255.0));
        assert!(near(p.span(1.0, 1.0).mean, 255.0));
        assert!(near(p.span(0.0, 0.0).mean, 0.0));
    }

    #[test]
    fn a_vertical_band_profiles_down_its_rows() {
        let p = Profile::read(&pixels(&[0, 0, 255, 255]), 1, 4, false);
        assert_eq!(p.len(), 4);
        assert!(near(p.span(0.0, 0.5).mean, 0.0));
        assert!(near(p.span(0.5, 1.0).mean, 255.0));
        assert!(near(p.stats().acutance, 0.0));
    }

    #[test]
    fn a_cell_on_a_bare_band_reads_its_own_stretch() {
        assert_eq!(cell(Paint::Dark, None, &st(30.0, 0.0, 0.0)), Paint::Light);
        assert_eq!(cell(Paint::Light, None, &st(230.0, 0.0, 0.0)), Paint::Dark);
        assert_eq!(
            cell(Paint::Dark, Some("transparent"), &st(30.0, 0.0, 0.0)),
            Paint::Light
        );
        assert_eq!(
            cell(Paint::Dark, Some("auto"), &st(230.0, 0.0, 0.0)),
            Paint::Dark
        );
    }

    #[test]
    fn a_cell_keeps_the_band_paint_when_the_band_has_a_fill_or_a_pin() {
        let dark = st(30.0, 0.0, 0.0);
        assert_eq!(
            cell(Paint::TranslucentDark, None, &dark),
            Paint::TranslucentDark
        );
        assert_eq!(
            cell(Paint::TranslucentLight, None, &dark),
            Paint::TranslucentLight
        );
        assert_eq!(cell(Paint::Maximized, None, &dark), Paint::Maximized);
        assert_eq!(cell(Paint::Dark, Some("dark"), &dark), Paint::Dark);
        let unsampled = Stats {
            mean: 0.0,
            std: 0.0,
            acutance: 0.0,
            sampled: false,
        };
        assert_eq!(cell(Paint::Dark, None, &unsampled), Paint::Dark);
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
