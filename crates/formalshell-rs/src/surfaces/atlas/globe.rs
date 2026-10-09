// Portions from omarchy-radio-atlas (MIT, Copyright 2026 Akshar Patel)

//! The globe in near-side perspective, countries off Natural
//! Earth lit from the upper left, stations as dots sized and faded by depth,
//! drag to spin with a kinetic coast, wheel to fly in. One draw list per
//! pose: the node keeps the same list, and so damages nothing, until the
//! pose, the stations, the selection or the palette moves.

use std::f64::consts::PI;
use std::sync::Arc;
use std::time::Instant;

use fs_media::radio::model::{self as rm, Feature, KineticOptions, KineticState, View};
use fs_media::radio::stations::Station;
use fs_theme::color::Rgba;
use vello_cpu::Pixmap;
use vello_cpu::kurbo::{self, BezPath, Circle, Shape as _};

use crate::scene::{Bitmap, Brush, VOp};

const COUNTRIES: &str = include_str!("../../../data/countries.json");

pub const HIT_RADIUS: f64 = 12.0;
const MINIMUM_SCALE: f64 = 0.72;
const MAXIMUM_SCALE: f64 = 24.0;
const LAUNCH_SPEED: f64 = 120.0;
const MAXIMUM_SPEED: f64 = 2400.0;
const DECELERATION: f64 = 1800.0;
const MAXIMUM_FRAME_TIME: f64 = 0.1;
/// The motion a release carries, in Wayland event milliseconds: the
/// samples this far back from the release.
const VELOCITY_WINDOW_MS: u32 = 80;
/// A pointer that sent no motion for this long before its release had
/// stopped, and launches nothing.
const STOPPED_MS: u32 = 40;
/// The shortest span a velocity is measured over, so two events a
/// millisecond apart cannot read as a flick.
const MINIMUM_SPAN_MS: u32 = 16;
/// QStyleHints::startDragDistance, past which a press is a drag.
const DRAG_THRESHOLD: f64 = 10.0;

struct Ring {
    world: Vec<[f64; 3]>,
    centroid: [f64; 3],
}

struct Outline {
    code: String,
    rings: Vec<Ring>,
}

/// countries.json parsed and turned into unit vectors, done once, off the
/// UI thread.
pub struct Countries {
    pub features: Vec<Feature>,
    outlines: Vec<Outline>,
}

impl std::fmt::Debug for Countries {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Countries({})", self.features.len())
    }
}

fn unit(latitude: f64, longitude: f64) -> Option<[f64; 3]> {
    let (lat, lon) = (latitude * PI / 180.0, longitude * PI / 180.0);
    if !lat.is_finite() || !lon.is_finite() {
        return None;
    }
    Some([lat.cos() * lon.cos(), lat.cos() * lon.sin(), lat.sin()])
}

pub fn load() -> Countries {
    let features = rm::parse_features(COUNTRIES);
    let mut outlines = Vec::new();
    for f in &features {
        let Some(polygons) = &f.polygons else { continue };
        let mut rings = Vec::new();
        for polygon in polygons {
            let Some(ring) = polygon.first() else { continue };
            let world: Vec<[f64; 3]> = ring.iter().filter_map(|p| unit(p[1], p[0])).collect();
            if world.len() < 3 {
                continue;
            }
            let c = world.iter().fold([0.0; 3], |a, p| [a[0] + p[0], a[1] + p[1], a[2] + p[2]]);
            let length = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt();
            let length = if length == 0.0 { 1.0 } else { length };
            rings.push(Ring { world, centroid: [c[0] / length, c[1] / length, c[2] / length] });
        }
        if !rings.is_empty() {
            let code = f.properties.as_ref().map(|p| p.code.to_uppercase()).unwrap_or_default();
            outlines.push(Outline { code, rings });
        }
    }
    Countries { features, outlines }
}

/// The satellite picture the globe wraps itself in: an equirectangular
/// RGB raster, longitude -180 at the left edge and the north pole at the
/// top, held only while the atlas is open.
pub struct Earth {
    width: usize,
    height: usize,
    /// Three bytes a texel and one past the end, so any texel reads as
    /// one little-endian u32.
    rgb: Vec<u8>,
}

impl Earth {
    fn new(width: usize, height: usize, mut rgb: Vec<u8>) -> Self {
        rgb.push(0);
        Self { width, height, rgb }
    }
}

impl std::fmt::Debug for Earth {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Earth({}x{})", self.width, self.height)
    }
}

/// The picture `FS_EARTH_IMAGE` names (the package's Blue Marble), decoded
/// off the UI thread.
pub fn load_earth() -> Result<Earth, String> {
    let path = std::env::var_os("FS_EARTH_IMAGE").ok_or("FS_EARTH_IMAGE is not set")?;
    let image = image::ImageReader::open(&path)
        .map_err(|e| format!("{}: {e}", path.to_string_lossy()))?
        .decode()
        .map_err(|e| format!("{}: {e}", path.to_string_lossy()))?
        .into_rgb8();
    let (width, height) = (image.width() as usize, image.height() as usize);
    if width < 2 || height < 2 {
        return Err(format!("{}: {width}x{height} is too small", path.to_string_lossy()));
    }
    Ok(Earth::new(width, height, image.into_raw()))
}

/// The run of pixels the sampler draws between two exactly projected
/// ones, and the shorter run it takes over the outer rim of the disc, where
/// the projection bends hardest.
const SPAN: i32 = 16;
const RIM_SPAN: i32 = 4;

/// atan2 to within 1e-5 rad, a tenth of a texel on a 4096 wide picture,
/// without the libm call per pixel.
#[inline(always)]
fn fast_atan2(y: f32, x: f32) -> f32 {
    let (ax, ay) = (x.abs(), y.abs());
    let (lo, hi) = if ax > ay { (ay, ax) } else { (ax, ay) };
    if hi == 0.0 {
        return 0.0;
    }
    let a = lo / hi;
    let s = a * a;
    let mut r = a * (0.999_977_26 + s * (-0.332_623_47 + s * (0.193_543_46 + s * (-0.116_432_87 + s * (0.052_653_32 + s * -0.011_721_2)))));
    if ay > ax {
        r = std::f32::consts::FRAC_PI_2 - r;
    }
    if x < 0.0 {
        r = std::f32::consts::PI - r;
    }
    if y < 0.0 { -r } else { r }
}

impl Earth {
    /// The near-side view of the picture over `area` (device pixels, the
    /// disc's box cut to the pane), centred at `centre` with `r` pixels to
    /// the unit and the camera `distance` sphere radii out, turned by
    /// `rot`, and lit by `light` the way the flat globe's land is.
    /// Pixels off the sphere stay clear; the caller clips the edge.
    ///
    /// The pixels land in a buffer out of `pool` nothing else holds any
    /// more (the frame before last's), so a drag maps no fresh pages a
    /// frame. `coarse` samples every other pixel of every other row and
    /// doubles each, for a globe in motion.
    fn sample(&self, pool: &mut Vec<Arc<Pixmap>>, coarse: bool, area: (i32, i32, i32, i32), centre: (f64, f64), r: f64, horizon_px: f64, distance: f64, rot: &Rot) -> Option<Bitmap> {
        let (x0, y0, x1, y1) = area;
        let (bw, bh) = ((x1 - x0).max(0) as usize, (y1 - y0).max(0) as usize);
        if bw == 0 || bh == 0 || bw > u16::MAX as usize || bh > u16::MAX as usize {
            return None;
        }
        let i = match pool.iter_mut().position(|p| Arc::get_mut(p).is_some()) {
            Some(i) => i,
            None => {
                pool.push(Arc::new(Pixmap::new(bw as u16, bh as u16)));
                pool.len() - 1
            }
        };
        let pixmap = Arc::get_mut(&mut pool[i])?;
        pixmap.resize(bw as u16, bh as u16);
        pixmap.set_may_have_transparency(true);
        let out = pixmap.data_as_u8_slice_mut();
        let (cx, cy) = (centre.0 as f32, centre.1 as f32);
        let inv_r = 1.0 / r as f32;
        let d = distance as f32;
        let dm1 = d - 1.0;
        let dd = d * dm1;
        let k2 = d * d - 1.0;
        let reach = horizon_px as f32 + 1.0;
        let inv_horizon = 1.0 / (horizon_px as f32).max(1.0);
        let (cl, sl) = (rot.cos_lat as f32, rot.sin_lat as f32);
        let (co, so) = (rot.cos_lon as f32, rot.sin_lon as f32);
        let l = light();
        let (l0, l1, l2) = (l[0] as f32, l[1] as f32, l[2] as f32);
        let (w, h) = (self.width, self.height);
        let (wf, hf) = (w as f32, h as f32);
        let to_x = wf / std::f32::consts::TAU;
        let to_y = hf / std::f32::consts::PI;
        let stride = w * 3;
        let tex = &self.rgb[..];
        let step = if coarse { 2 } else { 1 };
        for j in 0..bh {
            if coarse && j % 2 == 1 {
                out.copy_within((j - 1) * bw * 4..j * bw * 4, j * bw * 4);
                continue;
            }
            let py = (y0 + j as i32) as f32 + 0.5;
            let dy = py - cy;
            let half2 = reach * reach - dy * dy;
            let row = &mut out[j * bw * 4..(j + 1) * bw * 4];
            if half2 <= 0.0 {
                row.fill(0);
                continue;
            }
            let half = half2.sqrt();
            let xs = ((cx - half).floor() as i32).clamp(x0, x1);
            let xe = ((cx + half).ceil() as i32).clamp(xs, x1);
            row[..(xs - x0) as usize * 4].fill(0);
            row[(xe - x0) as usize * 4..].fill(0);
            let v = -dy * inv_r;
            let vv = v * v + dm1 * dm1;
            // The picture's coordinates and the light at a pixel centre,
            // fx unwrapped (-0.5 up to the width).
            let exact = |x: i32| {
                let u = ((x as f32) + 0.5 - cx) * inv_r;
                let a = u * u + vv;
                let disc = (dd * dd - a * k2).max(0.0);
                let t = (dd - disc.sqrt()) / a;
                let (vx, vy, vz) = (t * u, t * v, d - t * dm1);
                // The view frame back to the world: Rot::apply inverted.
                let p2 = cl * vy + sl * vz;
                let hz = cl * vz - sl * vy;
                let p0 = hz * co - vx * so;
                let p1 = hz * so + vx * co;
                let lon = fast_atan2(p1, p0);
                let lat = fast_atan2(p2, (1.0 - p2 * p2).max(0.0).sqrt());
                let shade = (0.62 + 0.45 * (vx * l0 + vy * l1 + vz * l2).max(0.0)).min(1.0);
                // The flat globe's limb darkening, folded in here rather
                // than painted as a second pass over the disc.
                let dx = x as f32 + 0.5 - cx;
                let edge = (((dx * dx + dy * dy).sqrt() * inv_horizon - 0.85) / 0.15).clamp(0.0, 1.0);
                let shade = shade * (1.0 - 0.55 * edge);
                (lon * to_x + wf * 0.5 - 0.5, hf * 0.5 - lat * to_y - 0.5, shade * 256.0)
            };
            // Exact every SPAN pixels and straight lines between: the
            // mapping bends slowly enough that the error stays under a
            // texel everywhere but the last pixels before the limb and
            // round a pole, where the picture's rows are one colour.
            let rim = (0.8 * horizon_px as f32).powi(2) - dy * dy;
            let mut a = xs;
            let mut at = exact(a);
            while a < xe {
                let off = (a as f32 + 0.5 - cx).abs().min((a as f32 + SPAN as f32 + 0.5 - cx).abs());
                let b = (a + if off * off < rim { SPAN } else { RIM_SPAN }).min(xe);
                let bt = exact(b);
                let mut dfx = bt.0 - at.0;
                if dfx > wf * 0.5 {
                    dfx -= wf;
                } else if dfx < -wf * 0.5 {
                    dfx += wf;
                }
                let n = 1.0 / (b - a) as f32;
                let (sx, sy, ss) = (dfx * n * step as f32, (bt.1 - at.1) * n * step as f32, (bt.2 - at.2) * n * step as f32);
                let (mut fx, mut fy, mut shade) = at;
                for x in (a..b).step_by(step) {
                    let fyc = fy.clamp(0.0, hf - 1.0);
                    let (gx, gy) = (fx.floor(), fyc.floor());
                    let (wx, wy) = (((fx - gx) * 256.0) as u32, ((fyc - gy) * 256.0) as u32);
                    let mut tx0 = gx as i32;
                    if !(0..w as i32).contains(&tx0) {
                        tx0 = tx0.rem_euclid(w as i32);
                    }
                    let tx0 = tx0 as usize;
                    let tx1 = if tx0 + 1 == w { 0 } else { tx0 + 1 };
                    let ty0 = gy as usize;
                    let ty1 = (ty0 + 1).min(h - 1);
                    let (r0, r1) = (ty0 * stride, ty1 * stride);
                    let texel = |i: usize| u32::from_le_bytes(tex[i..i + 4].try_into().unwrap_or([0; 4]));
                    let (p00, p01) = (texel(r0 + tx0 * 3), texel(r0 + tx1 * 3));
                    let (p10, p11) = (texel(r1 + tx0 * 3), texel(r1 + tx1 * 3));
                    // Red and blue lerped side by side in one word, green
                    // on its own; the fourth byte is the next texel's red.
                    let lerp = |a: u32, b: u32, t: u32| ((a * (256 - t) + b * t) >> 8) & 0x00ff_00ff;
                    let rb = |p: u32| p & 0x00ff_00ff;
                    let g = |p: u32| (p >> 8) & 0xff;
                    let rb = lerp(lerp(rb(p00), rb(p01), wx), lerp(rb(p10), rb(p11), wx), wy);
                    let g = lerp(lerp(g(p00), g(p01), wx), lerp(g(p10), g(p11), wx), wy);
                    let k = shade as u32;
                    let px = (((rb * k) >> 8) & 0x00ff_00ff) | (((g * k) >> 8) << 8) | 0xff00_0000;
                    let o = (x - x0) as usize * 4;
                    row[o..o + 4].copy_from_slice(&px.to_le_bytes());
                    if coarse && x + 1 < b {
                        row[o + 4..o + 8].copy_from_slice(&px.to_le_bytes());
                    }
                    fx += sx;
                    fy += sy;
                    shade += ss;
                }
                a = b;
                at = bt;
            }
        }
        let pixmap = pool[i].clone();
        pool.truncate(3);
        Some(Bitmap { pixmap })
    }
}

fn grid() -> Vec<Vec<[f64; 3]>> {
    let mut out = Vec::new();
    for latitude in (-60..=60).step_by(30) {
        out.push((-180..=180).step_by(3).filter_map(|lon| unit(latitude as f64, lon as f64)).collect());
    }
    for meridian in (-150..=180).step_by(30) {
        out.push((-90..=90).step_by(3).filter_map(|lat| unit(lat as f64, meridian as f64)).collect());
    }
    out
}

/// The palette the globe paints in.
#[derive(Clone, Copy, PartialEq)]
pub struct Ink {
    pub sphere: Rgba,
    pub land: Rgba,
    pub grid: Rgba,
    pub outline: Rgba,
    pub signal: Rgba,
    pub accent: Rgba,
}

fn rgba(r: f64, g: f64, b: f64, a: f64) -> Rgba {
    Rgba { r: r as f32, g: g as f32, b: b as f32, a: a as f32 }
}

fn with_alpha(c: Rgba, a: f64) -> Rgba {
    Rgba { a: a as f32, ..c }
}

fn mix(from: Rgba, to: Rgba, amount: f64, alpha: f64) -> Rgba {
    let t = amount.clamp(0.0, 1.0) as f32;
    Rgba { r: from.r + (to.r - from.r) * t, g: from.g + (to.g - from.g) * t, b: from.b + (to.b - from.b) * t, a: alpha as f32 }
}

fn hsv(c: Rgba) -> (f64, f64, f64) {
    let (r, g, b) = (c.r as f64, c.g as f64, c.b as f64);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let d = max - min;
    let h = if d == 0.0 {
        0.0
    } else if max == r {
        ((g - b) / d).rem_euclid(6.0)
    } else if max == g {
        (b - r) / d + 2.0
    } else {
        (r - g) / d + 4.0
    } / 6.0;
    (h, if max == 0.0 { 0.0 } else { d / max }, max)
}

fn from_hsv(h: f64, s: f64, v: f64, a: f32) -> Rgba {
    let i = (h * 6.0).floor();
    let f = h * 6.0 - i;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s));
    let (r, g, b) = match i as i64 % 6 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    rgba(r, g, b, a as f64)
}

/// Qt.darker: the HSV value divided by `factor`.
fn darker(c: Rgba, factor: f64) -> Rgba {
    let (h, s, v) = hsv(c);
    from_hsv(h, s, v / factor, c.a)
}

/// Qt.lighter: the value multiplied, saturation giving way past white.
fn lighter(c: Rgba, factor: f64) -> Rgba {
    let (h, mut s, mut v) = hsv(c);
    v *= factor;
    if v > 1.0 {
        s = (s - (v - 1.0)).max(0.0);
        v = 1.0;
    }
    from_hsv(h, s, v, c.a)
}

/// Camera-space light, x right, y up, z toward the viewer: upper left and a
/// little in front, so the lit side faces the reader.
fn light() -> [f64; 3] {
    let (x, y, z) = (-0.55, 0.6, 0.58);
    let l = ((x * x + y * y + z * z) as f64).sqrt();
    [x / l, y / l, z / l]
}

fn lambert(n: [f64; 3]) -> f64 {
    let l = light();
    (n[0] * l[0] + n[1] * l[1] + n[2] * l[2]).max(0.0)
}

struct Point {
    station: usize,
    world: [f64; 3],
    visible: bool,
    x: f64,
    y: f64,
}

#[derive(Default)]
struct Drag {
    press: Option<(f64, f64)>,
    active: bool,
    last: (f64, f64),
    /// Recent positions by the Wayland event's own time, never the loop's:
    /// motion the compositor coalesced lands in one loop turn.
    samples: std::collections::VecDeque<(u32, f64, f64)>,
}

impl Drag {
    fn sample(&mut self, time: u32, x: f64, y: f64) {
        self.samples.push_back((time, x, y));
        while self.samples.front().is_some_and(|&(t, ..)| time.wrapping_sub(t) > VELOCITY_WINDOW_MS * 2) {
            self.samples.pop_front();
        }
    }

    /// The velocity a release at `time` carries, in pixels a second: the
    /// travel over the window before it, spread over the time up to the
    /// release so a pointer slowing into it carries less. Nothing once it
    /// had stopped.
    fn release_velocity(&self, time: u32) -> (f64, f64) {
        let Some(&(last_t, lx, ly)) = self.samples.back() else { return (0.0, 0.0) };
        if time.wrapping_sub(last_t) > STOPPED_MS {
            return (0.0, 0.0);
        }
        let Some(&(first_t, fx, fy)) = self.samples.iter().find(|&&(t, ..)| time.wrapping_sub(t) <= VELOCITY_WINDOW_MS) else {
            return (0.0, 0.0);
        };
        let span = f64::from(time.wrapping_sub(first_t).max(MINIMUM_SPAN_MS)) / 1000.0;
        ((lx - fx) / span, (ly - fy) / span)
    }
}

/// What a pointer gesture on the globe asked of the atlas.
#[derive(Debug, PartialEq)]
pub enum Out {
    None,
    Interaction,
    Station(Station),
    Country(String, String),
}

#[derive(Clone, PartialEq)]
struct Key {
    pose: [f64; 3],
    size: (f64, f64, f64, f64),
    ink: [u32; 6],
    alpha: u32,
    active: String,
    selected: String,
    highlight: String,
    stations: u64,
    imagery: bool,
    moving: bool,
}

pub struct Globe {
    pub countries: Option<Arc<Countries>>,
    /// The satellite picture, while the atlas is open and it decoded; the
    /// flat globe stands in without it.
    pub earth: Option<Arc<Earth>>,
    /// The last few frames' pixels, for the sampler to draw into again.
    sampled: Vec<Arc<Pixmap>>,
    grid: Vec<Vec<[f64; 3]>>,
    pub stations: Vec<Station>,
    stations_version: u64,
    points: Vec<Point>,
    pub centre_latitude: f64,
    pub centre_longitude: f64,
    pub scale: f64,
    /// The pane's box on the surface.
    pub rect: (f64, f64, f64, f64),
    pub active_country: String,
    pub selected: Option<Station>,
    pub hovered: Option<Station>,
    pub hover: (f64, f64),
    pub highlighted: Option<Station>,
    pub highlight: (f64, f64),
    velocity: (f64, f64),
    pub kinetic: bool,
    last_frame: Option<Instant>,
    drag: Drag,
    suppress_tap: bool,
    drawn: Option<(Key, Arc<Vec<VOp>>)>,
}

impl Default for Globe {
    fn default() -> Self {
        Self {
            countries: None,
            earth: None,
            sampled: Vec::new(),
            grid: grid(),
            stations: Vec::new(),
            stations_version: 0,
            points: Vec::new(),
            centre_latitude: 18.0,
            centre_longitude: -20.0,
            scale: 1.0,
            rect: (0.0, 0.0, 0.0, 0.0),
            active_country: String::new(),
            selected: None,
            hovered: None,
            hover: (0.0, 0.0),
            highlighted: None,
            highlight: (0.0, 0.0),
            velocity: (0.0, 0.0),
            kinetic: false,
            last_frame: None,
            drag: Drag::default(),
            suppress_tap: false,
            drawn: None,
        }
    }
}

impl Globe {
    fn size(&self) -> (f64, f64) {
        (self.rect.2, self.rect.3)
    }

    fn radius(&self) -> f64 {
        let (w, h) = self.size();
        rm::view_radius(w, h, self.scale)
    }

    fn distance(&self) -> f64 {
        rm::view_distance(self.scale)
    }

    fn degrees_per_pixel(&self) -> f64 {
        180.0 / PI / self.radius().max(1.0)
    }

    fn longitude_sensitivity(&self) -> f64 {
        self.degrees_per_pixel() / (self.centre_latitude * PI / 180.0).cos().max(0.2)
    }

    fn view(&self) -> View {
        let (w, h) = self.size();
        View { width: w, height: h, scale: self.scale, centre_latitude: self.centre_latitude, centre_longitude: self.centre_longitude }
    }

    /// Whether the globe is turning under a drag or a coast, when the
    /// satellite picture is sampled coarse.
    fn moving(&self) -> bool {
        self.kinetic || self.drag.active
    }

    /// Whether anything moves on its own: the kinetic coast.
    pub fn animating(&self) -> bool {
        self.kinetic
    }

    pub fn set_stations(&mut self, stations: Vec<Station>) {
        if stations == self.stations {
            return;
        }
        self.stations = stations;
        self.stations_version += 1;
        self.points = self
            .stations
            .iter()
            .enumerate()
            .filter_map(|(i, s)| Some(Point { station: i, world: unit(s.latitude?, s.longitude?)?, visible: false, x: 0.0, y: 0.0 }))
            .collect();
        self.refresh_landing();
    }

    pub fn set_selected(&mut self, station: Option<Station>) {
        let uuid = |s: &Option<Station>| s.as_ref().map(|s| s.uuid.clone()).unwrap_or_default();
        if uuid(&station) != uuid(&self.selected) {
            self.clear_landing();
        }
        self.selected = station;
    }

    pub fn set_countries(&mut self, countries: Arc<Countries>) {
        self.countries = Some(countries);
        if !self.active_country.is_empty() {
            let code = self.active_country.clone();
            self.focus_country(&code);
        }
    }

    fn clear_landing(&mut self) {
        self.highlighted = None;
        self.highlight = (0.0, 0.0);
    }

    fn refresh_landing(&mut self) {
        let Some(h) = &self.highlighted else { return };
        match self.stations.iter().find(|s| s.uuid == h.uuid).cloned() {
            Some(s) => {
                self.highlighted = Some(s);
                self.update_highlight();
            }
            None => self.clear_landing(),
        }
    }

    fn update_highlight(&mut self) {
        let Some(h) = &self.highlighted else { return };
        match rm::station_position(h, self.view()) {
            Some(p) => self.highlight = (p.x, p.y),
            None => self.clear_landing(),
        }
    }

    pub fn stop(&mut self, clear_landing: bool) {
        self.kinetic = false;
        self.velocity = (0.0, 0.0);
        self.last_frame = None;
        if clear_landing {
            self.clear_landing();
        }
    }

    fn start(&mut self, vx: f64, vy: f64, now: Instant) {
        let launch = rm::kinetic_launch_velocity(vx, vy, LAUNCH_SPEED, MAXIMUM_SPEED);
        if !launch.active {
            return;
        }
        self.clear_landing();
        self.hovered = None;
        self.velocity = (launch.x, launch.y);
        self.kinetic = true;
        self.last_frame = Some(now);
    }

    fn finish(&mut self) {
        self.kinetic = false;
        self.velocity = (0.0, 0.0);
        self.hovered = None;
        let (w, h) = self.size();
        let excluded = self.selected.as_ref().map(|s| s.uuid.clone()).unwrap_or_default();
        self.highlighted =
            rm::nearest_visible_station(&self.stations, self.centre_latitude, self.centre_longitude, &excluded, w, h, self.scale).cloned();
        self.update_highlight();
    }

    /// FrameAnimation's tick: one step of the coast.
    pub fn tick(&mut self, now: Instant) {
        if !self.kinetic {
            return;
        }
        let dt = self.last_frame.map_or(0.0, |l| now.saturating_duration_since(l).as_secs_f64());
        self.last_frame = Some(now);
        if dt > MAXIMUM_FRAME_TIME {
            return self.stop(true);
        }
        if dt <= 0.0 {
            return;
        }
        let step = rm::advance_kinetic_rotation(
            KineticState { longitude: self.centre_longitude, latitude: self.centre_latitude, velocity_x: self.velocity.0, velocity_y: self.velocity.1 },
            dt,
            KineticOptions {
                deceleration: Some(DECELERATION),
                scale: Some(1.0),
                longitude_sensitivity: Some(self.longitude_sensitivity()),
                latitude_sensitivity: Some(self.degrees_per_pixel()),
                minimum_latitude: Some(-78.0),
                maximum_latitude: Some(78.0),
            },
        );
        self.velocity = (step.velocity_x, step.velocity_y);
        self.centre_longitude = step.longitude;
        self.centre_latitude = step.latitude;
        self.update_highlight();
        if !step.active {
            self.finish();
        }
    }

    fn rotate_by(&mut self, dx: f64, dy: f64) {
        self.centre_longitude = rm::wrap_longitude(self.centre_longitude - dx * self.longitude_sensitivity());
        self.centre_latitude = (self.centre_latitude + dy * self.degrees_per_pixel()).clamp(-78.0, 78.0);
        self.update_highlight();
    }

    pub fn focus_coordinate(&mut self, latitude: f64, longitude: f64) {
        if !latitude.is_finite() || !longitude.is_finite() {
            return;
        }
        self.stop(true);
        self.centre_latitude = latitude.clamp(-78.0, 78.0);
        self.centre_longitude = rm::wrap_longitude(longitude);
    }

    pub fn focus_country(&mut self, code: &str) {
        let centre = self.countries.as_ref().and_then(|c| rm::country_centre(&c.features, code));
        if let Some(c) = centre {
            self.focus_coordinate(c.latitude, c.longitude);
        }
    }

    fn station_under(&self, x: f64, y: f64) -> Option<&Station> {
        let mut nearest = None;
        let mut best = HIT_RADIUS * HIT_RADIUS;
        for p in self.points.iter().filter(|p| p.visible) {
            let d = (p.x - x).powi(2) + (p.y - y).powi(2);
            if d > best {
                continue;
            }
            nearest = Some(&self.stations[p.station]);
            best = d;
        }
        nearest
    }

    fn activate_at(&mut self, x: f64, y: f64) -> Out {
        self.clear_landing();
        if let Some(s) = self.station_under(x, y) {
            return Out::Station(s.clone());
        }
        let (w, h) = self.size();
        let r = self.radius();
        let Some(c) = rm::unproject((x - w / 2.0) / r, -(y - h / 2.0) / r, self.centre_latitude, self.centre_longitude, self.distance()) else {
            return Out::None;
        };
        let Some(countries) = &self.countries else { return Out::None };
        match rm::country_at(&countries.features, c.latitude, c.longitude) {
            Some(p) if !p.code.is_empty() && p.code != "-99" => {
                Out::Country(p.code.to_uppercase(), if p.name.is_empty() { p.code.clone() } else { p.name.clone() })
            }
            _ => Out::None,
        }
    }

    fn local(&self, x: f64, y: f64) -> (f64, f64) {
        (x - self.rect.0, y - self.rect.1)
    }

    pub fn contains(&self, x: f64, y: f64) -> bool {
        let (lx, ly) = self.local(x, y);
        lx >= 0.0 && ly >= 0.0 && lx < self.rect.2 && ly < self.rect.3
    }

    /// Whether the cursor shows the grabbing shape.
    pub fn grabbing(&self) -> bool {
        self.drag.press.is_some()
    }

    pub fn over_station(&self) -> bool {
        self.hovered.is_some()
    }

    /// The pointer moved over the globe, in surface coordinates, at the
    /// Wayland event's `time` (none for an enter).
    pub fn motion(&mut self, x: f64, y: f64, time: Option<u32>) -> Out {
        let (lx, ly) = self.local(x, y);
        self.hover = (lx, ly);
        if let Some((px, py)) = self.drag.press {
            if !self.drag.active {
                if ((lx - px).powi(2) + (ly - py).powi(2)).sqrt() < DRAG_THRESHOLD {
                    return Out::None;
                }
                self.stop(true);
                self.drag.active = true;
                self.suppress_tap = false;
                self.hovered = None;
                self.drag.last = (px, py);
                self.drag.samples.clear();
            }
            if let Some(time) = time {
                self.drag.sample(time, lx, ly);
            }
            let (dx, dy) = (lx - self.drag.last.0, ly - self.drag.last.1);
            self.drag.last = (lx, ly);
            self.rotate_by(dx, dy);
            return Out::Interaction;
        }
        self.hovered = if self.kinetic { None } else { self.station_under(lx, ly).cloned() };
        Out::None
    }

    pub fn leave(&mut self) {
        self.hovered = None;
    }

    pub fn press(&mut self, x: f64, y: f64) -> Out {
        let (lx, ly) = self.local(x, y);
        let caught = self.kinetic;
        self.stop(true);
        self.suppress_tap = caught;
        self.hovered = None;
        self.drag = Drag { press: Some((lx, ly)), ..Drag::default() };
        Out::Interaction
    }

    /// The button let go at the Wayland event's `time`; `now` starts the
    /// coast's own clock.
    pub fn release(&mut self, x: f64, y: f64, time: u32, now: Instant) -> Out {
        let (lx, ly) = self.local(x, y);
        let drag = std::mem::take(&mut self.drag);
        if drag.press.is_none() {
            return Out::None;
        }
        if drag.active {
            let (vx, vy) = drag.release_velocity(time);
            self.start(vx, vy, now);
            return Out::None;
        }
        if std::mem::take(&mut self.suppress_tap) {
            return Out::None;
        }
        let out = self.activate_at(lx, ly);
        self.hovered = self.station_under(lx, ly).cloned();
        out
    }

    /// A wheel notch (positive away from the reader) zooms in.
    pub fn wheel(&mut self, angle_delta: f64) {
        self.stop(true);
        self.suppress_tap = false;
        self.hovered = None;
        self.scale = (self.scale * (angle_delta / 720.0).exp()).clamp(MINIMUM_SCALE, MAXIMUM_SCALE);
        self.update_highlight();
    }

    /// The draw list for the current pose at `alpha`, the same `Arc` while
    /// nothing on the globe moved.
    pub fn paint(&mut self, ink: &Ink, alpha: f32) -> Arc<Vec<VOp>> {
        let bits = |c: Rgba| u32::from_le_bytes(c.to_u8());
        let key = Key {
            pose: [self.centre_latitude, self.centre_longitude, self.scale],
            size: self.rect,
            ink: [bits(ink.sphere), bits(ink.land), bits(ink.grid), bits(ink.outline), bits(ink.signal), bits(ink.accent)],
            alpha: alpha.to_bits(),
            active: self.active_country.clone(),
            selected: self.selected.as_ref().map(|s| s.uuid.clone()).unwrap_or_default(),
            highlight: self.highlighted.as_ref().map(|s| s.uuid.clone()).unwrap_or_default(),
            stations: self.stations_version + if self.countries.is_some() { 1 << 40 } else { 0 },
            imagery: self.earth.is_some(),
            moving: self.moving(),
        };
        if let Some((k, ops)) = &self.drawn
            && *k == key
        {
            return ops.clone();
        }
        let ops = Arc::new(self.build(ink, alpha));
        self.drawn = Some((key, ops.clone()));
        ops
    }

    /// Lets go of the satellite picture and every frame drawn from it.
    pub fn drop_earth(&mut self) {
        self.earth = None;
        self.drawn = None;
        self.sampled.clear();
    }

    fn build(&mut self, ink: &Ink, alpha: f32) -> Vec<VOp> {
        let started = Instant::now();
        let mut ops = Vec::new();
        let (ox, oy, w, h) = self.rect;
        let r = self.radius();
        if !r.is_finite() || r <= 0.0 || w <= 0.0 || h <= 0.0 {
            return ops;
        }
        let fade = |c: Rgba| Rgba { a: c.a * alpha, ..c };
        let solid = |c: Rgba| Brush::Solid(fade(c));
        let (cx, cy) = (ox + w / 2.0, oy + h / 2.0);
        let disc = rm::horizon_radius(w, h, self.scale);
        let distance = self.distance();
        let circle = |radius: f64| Circle::new((cx, cy), radius.max(0.0)).to_path(0.1);
        ops.push(VOp::Clip(kurbo::Rect::new(ox, oy, ox + w, oy + h).to_path(0.1)));

        // The ocean, lit from the point facing the light.
        let l = light();
        let lit_k = r * (distance - 1.0) / (distance - l[2]);
        let lit = (cx + l[0] * lit_k, cy - l[1] * lit_k);
        let stops = vec![
            (0.0, fade(mix(ink.sphere, ink.outline, 0.34, 1.0))),
            (0.3, fade(mix(ink.sphere, ink.outline, 0.16, 1.0))),
            (0.65, fade(ink.sphere)),
            (1.0, fade(darker(ink.sphere, 2.5))),
        ];
        let earth = self.earth.clone();
        if earth.is_none() {
            ops.push(VOp::Fill(circle(disc), Brush::Radial { centre: lit, r0: disc * 0.05, r1: disc * 2.1, stops }));
        }

        ops.push(VOp::Clip(circle(disc - 0.5)));
        let (lat, lon) = (self.centre_latitude * PI / 180.0, self.centre_longitude * PI / 180.0);
        let rot = Rot { sin_lat: lat.sin(), cos_lat: lat.cos(), sin_lon: lon.sin(), cos_lon: lon.cos() };
        let mut sampled = None;
        let moving = self.moving();
        if let Some(earth) = &earth {
            let area = (
                ((cx - disc - 1.0).floor().max(ox.floor())) as i32,
                ((cy - disc - 1.0).floor().max(oy.floor())) as i32,
                ((cx + disc + 1.0).ceil().min((ox + w).ceil())) as i32,
                ((cy + disc + 1.0).ceil().min((oy + h).ceil())) as i32,
            );
            let t = Instant::now();
            if let Some(image) = earth.sample(&mut self.sampled, moving, area, (cx, cy), r, disc, distance, &rot) {
                let px = image.pixmap.width() as u64 * image.pixmap.height() as u64;
                ops.push(VOp::Image(image, (area.0 as f64, area.1 as f64), alpha));
                sampled = Some((t.elapsed().as_micros(), px));
            }
        }
        let horizon = 1.0 / distance;
        let k = |depth: f64| r * (distance - 1.0) / (distance - depth);

        // The graticule, each segment thinning and fading toward the limb.
        let base = (r / 500.0).clamp(0.7, 1.5);
        let grid_ink = with_alpha(ink.grid, if earth.is_some() { 0.18 } else { 0.3 });
        for curve in &self.grid {
            let mut last: Option<(f64, f64)> = None;
            for p in curve {
                let [x, y, z] = rot.apply(p);
                if z < horizon {
                    last = None;
                    continue;
                }
                let at = (cx + x * k(z), cy - y * k(z));
                if let Some(prev) = last {
                    let near = rm::horizon_depth(z, distance);
                    let mut path = BezPath::new();
                    path.move_to(prev);
                    path.line_to(at);
                    let c = with_alpha(grid_ink, grid_ink.a as f64 * (0.25 + near * 0.75));
                    ops.push(VOp::Stroke(path, solid(c), base * (0.45 + near * 0.55)));
                }
                last = Some(at);
            }
        }

        // The countries, Lambert-shaded off each ring's centroid.
        if let Some(countries) = self.countries.clone() {
            let horizon_screen = r * rm::horizon_ratio(distance);
            let active = self.active_country.to_uppercase();
            let land_dark = darker(ink.sphere, 1.6);
            let land_lit = lighter(ink.land, 1.5);
            for country in &countries.outlines {
                let is_active = !active.is_empty() && country.code == active;
                for ring in &country.rings {
                    let n = rot.apply(&ring.centroid);
                    let shade = lambert(n);
                    let near = rm::horizon_depth(n[2], distance);
                    // Over the satellite picture only the active country
                    // takes a fill, a wash of the accent, and borders stay
                    // hairlines.
                    let fill = if is_active && earth.is_some() {
                        Some(with_alpha(ink.accent, 0.3))
                    } else if is_active {
                        Some(mix(ink.sphere, ink.accent, 0.25 + shade * 0.35, 0.9))
                    } else if earth.is_some() {
                        None
                    } else {
                        Some(mix(land_dark, land_lit, 0.12 + shade * 0.88, 0.97))
                    };
                    let stroke = if is_active {
                        with_alpha(ink.accent, 0.95)
                    } else if earth.is_some() {
                        with_alpha(ink.outline, 0.08 + near * 0.22)
                    } else {
                        with_alpha(ink.outline, 0.12 + near * 0.3)
                    };
                    let width = if is_active { 1.5 } else { 0.35 + near * 0.55 };
                    let projected: Vec<[f64; 3]> = ring.world.iter().map(|p| rot.apply(p)).collect();
                    let screen = |p: &[f64; 3]| (cx + p[0] * k(p[2]), cy - p[1] * k(p[2]));
                    let Some(hidden) = projected.iter().position(|p| p[2] < horizon) else {
                        let mut path = BezPath::new();
                        for (i, p) in projected.iter().enumerate() {
                            if i == 0 { path.move_to(screen(p)) } else { path.line_to(screen(p)) }
                        }
                        path.close_path();
                        if let Some(fill) = fill {
                            ops.push(VOp::Fill(path.clone(), solid(fill)));
                        }
                        ops.push(VOp::Stroke(path, solid(stroke), width));
                        continue;
                    };
                    // A ring crossing the horizon: each visible run closed
                    // round the horizon circle's arc.
                    let points = projected.len();
                    let mut prev = projected[hidden];
                    let mut path: Option<BezPath> = None;
                    let mut start_angle = 0.0;
                    let edge = |a: [f64; 3], b: [f64; 3]| {
                        let t = (a[2] - horizon) / (a[2] - b[2]);
                        let (x, y) = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t);
                        let len = (x * x + y * y).sqrt();
                        let len = if len == 0.0 { 1.0 } else { len };
                        (x / len, y / len)
                    };
                    for step in 1..=points {
                        let cur = projected[(hidden + step) % points];
                        let (pv, cv) = (prev[2] >= horizon, cur[2] >= horizon);
                        if !pv && cv {
                            let (ex, ey) = edge(prev, cur);
                            start_angle = (-ey).atan2(ex);
                            let mut p = BezPath::new();
                            p.move_to((cx + ex * horizon_screen, cy - ey * horizon_screen));
                            p.line_to(screen(&cur));
                            path = Some(p);
                        } else if pv && cv {
                            if let Some(p) = &mut path {
                                p.line_to(screen(&cur));
                            }
                        } else if pv && !cv && let Some(mut p) = path.take() {
                            let (lx, ly) = edge(prev, cur);
                            let end_angle = (-ly).atan2(lx);
                            let clockwise = (start_angle - end_angle + PI * 2.0).rem_euclid(PI * 2.0);
                            p.line_to((cx + lx * horizon_screen, cy - ly * horizon_screen));
                            ops.push(VOp::Stroke(p.clone(), solid(stroke), width));
                            arc_to(&mut p, (cx, cy), horizon_screen, end_angle, start_angle, clockwise > PI);
                            p.close_path();
                            if let Some(fill) = fill {
                                ops.push(VOp::Fill(p, solid(fill)));
                            }
                        }
                        prev = cur;
                    }
                }
            }
        }

        // Limb darkening over the last stretch before the horizon; the
        // satellite picture carries its own.
        let shade = darker(ink.sphere, 3.0);
        let limb = vec![(0.0, fade(with_alpha(shade, 0.0))), (0.85, fade(with_alpha(shade, 0.0))), (1.0, fade(with_alpha(shade, 0.55)))];
        let square = kurbo::Rect::new(cx - disc, cy - disc, cx + disc, cy + disc).to_path(0.1);
        if earth.is_none() {
            ops.push(VOp::Fill(square, Brush::Radial { centre: (cx, cy), r0: 0.0, r1: disc, stops: limb }));
        }

        self.paint_signals(&mut ops, ink, alpha, &rot, (cx, cy));
        ops.push(VOp::Pop);

        // The atmosphere: a thin rim of the accent just outside the horizon.
        let rim = r * 0.04;
        let stops = vec![(0.0, fade(with_alpha(ink.accent, 0.35))), (1.0, fade(with_alpha(ink.accent, 0.0)))];
        ops.push(VOp::Stroke(circle(disc + rim / 2.0), Brush::Radial { centre: (cx, cy), r0: disc, r1: disc + rim, stops }, rim));
        ops.push(VOp::Stroke(circle(disc), solid(with_alpha(ink.outline, 0.3)), 1.0));
        ops.push(VOp::Pop);
        if crate::tracing() {
            let (sample_us, px) = sampled.unwrap_or((0, 0));
            crate::trace(format!(
                "atlas globe build_us={} sample_us={sample_us} px={px} imagery={} coarse={}",
                started.elapsed().as_micros(),
                earth.is_some(),
                self.moving()
            ));
        }
        ops
    }

    fn paint_signals(&mut self, ops: &mut Vec<VOp>, ink: &Ink, alpha: f32, rot: &Rot, (cx, cy): (f64, f64)) {
        let (ox, oy, w, h) = self.rect;
        let r = self.radius();
        let distance = self.distance();
        let horizon = 1.0 / distance;
        let selected = self.selected.as_ref().map(|s| s.uuid.clone());
        let highlight = self.highlighted.as_ref().map(|s| s.uuid.clone());
        let fade = |c: Rgba| Rgba { a: c.a * alpha, ..c };
        let marker = with_alpha(ink.signal, 1.0);
        for p in &mut self.points {
            let [x, y, z] = rot.apply(&p.world);
            p.visible = z >= horizon;
            if !p.visible {
                continue;
            }
            let k = r * (distance - 1.0) / (distance - z);
            p.x = cx - ox + x * k;
            p.y = cy - oy - y * k;
            p.visible = p.x >= -HIT_RADIUS && p.x <= w + HIT_RADIUS && p.y >= -HIT_RADIUS && p.y <= h + HIT_RADIUS;
            if !p.visible {
                continue;
            }
            let uuid = &self.stations[p.station].uuid;
            let is_selected = selected.as_ref() == Some(uuid);
            let is_highlighted = !is_selected && highlight.as_ref() == Some(uuid);
            let depth = rm::horizon_depth(z, distance);
            let perspective = (distance - 1.0) / (distance - z);
            let radius = if is_selected {
                4.2
            } else if is_highlighted {
                3.7
            } else {
                (1.2 + depth * 1.6) * perspective
            };
            let at = (ox + p.x, oy + p.y);
            let c = if is_selected || is_highlighted { ink.accent } else { with_alpha(marker, 0.25 + depth * 0.7) };
            let dot = Circle::new(at, radius).to_path(0.1);
            if self.earth.is_some() && !is_selected && !is_highlighted {
                // A rim in the card's own colour keeps a small dot apart
                // from the picture under it.
                ops.push(VOp::Stroke(dot.clone(), Brush::Solid(fade(with_alpha(ink.sphere, 0.25 + depth * 0.55))), 1.2));
            }
            ops.push(VOp::Fill(dot, Brush::Solid(fade(c))));
            if is_selected || is_highlighted {
                let ring = if is_selected { with_alpha(ink.accent, 0.72) } else { with_alpha(ink.accent, 0.92) };
                let path = Circle::new(at, if is_selected { 8.5 } else { 7.5 }).to_path(0.1);
                ops.push(VOp::Stroke(path, Brush::Solid(fade(ring)), if is_selected { 1.2 } else { 1.4 }));
            }
        }
    }
}

struct Rot {
    sin_lat: f64,
    cos_lat: f64,
    sin_lon: f64,
    cos_lon: f64,
}

impl Rot {
    /// A world unit vector in the view frame: x right, y up, z toward the
    /// camera.
    fn apply(&self, p: &[f64; 3]) -> [f64; 3] {
        let horizontal = p[0] * self.cos_lon + p[1] * self.sin_lon;
        [
            p[1] * self.cos_lon - p[0] * self.sin_lon,
            self.cos_lat * p[2] - self.sin_lat * horizontal,
            self.sin_lat * p[2] + self.cos_lat * horizontal,
        ]
    }
}

/// Canvas2D's `arc(cx, cy, r, from, to, anticlockwise)` appended to a path
/// whose pen already sits at the arc's start.
fn arc_to(path: &mut BezPath, centre: (f64, f64), radius: f64, from: f64, to: f64, anticlockwise: bool) {
    let tau = PI * 2.0;
    let sweep = if anticlockwise { -(from - to).rem_euclid(tau) } else { (to - from).rem_euclid(tau) };
    let arc = kurbo::Arc::new(centre, (radius, radius), from, sweep, 0.0);
    arc.to_cubic_beziers(0.1, |p1, p2, p| path.curve_to(p1, p2, p));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_outlines_load() {
        let c = load();
        assert!(c.features.len() > 150);
        assert!(c.outlines.iter().any(|o| o.code == "FR"));
    }

    #[test]
    fn qt_darker_and_lighter_move_the_value() {
        let c = rgba(0.5, 0.25, 0.25, 1.0);
        let d = darker(c, 2.0);
        assert!((d.r - 0.25).abs() < 1e-4 && (d.g - 0.125).abs() < 1e-4);
        let l = lighter(rgba(0.8, 0.4, 0.4, 1.0), 1.5);
        assert!((l.r - 1.0).abs() < 1e-4);
    }

    #[test]
    fn a_still_globe_hands_back_the_same_list() {
        let mut g = Globe { rect: (0.0, 0.0, 400.0, 300.0), countries: Some(Arc::new(load())), ..Globe::default() };
        let ink = Ink { sphere: Rgba::hex(0x101010ff), land: Rgba::hex(0x303030ff), grid: Rgba::hex(0x404040ff), outline: Rgba::hex(0x808080ff), signal: Rgba::hex(0xff8800ff), accent: Rgba::hex(0xff8800ff) };
        let a = g.paint(&ink, 1.0);
        let b = g.paint(&ink, 1.0);
        assert!(Arc::ptr_eq(&a, &b));
        g.wheel(120.0);
        assert!(!Arc::ptr_eq(&a, &g.paint(&ink, 1.0)));
    }

    #[test]
    fn a_tap_on_a_station_activates_it() {
        let mut g = Globe { rect: (10.0, 20.0, 400.0, 300.0), ..Globe::default() };
        let s = Station { uuid: "u".into(), name: "Smoke".into(), latitude: Some(18.0), longitude: Some(-20.0), ..Station::default() };
        g.set_stations(vec![s.clone()]);
        let ink = Ink { sphere: Rgba::hex(0x101010ff), land: Rgba::hex(0x303030ff), grid: Rgba::hex(0x404040ff), outline: Rgba::hex(0x808080ff), signal: Rgba::hex(0xff8800ff), accent: Rgba::hex(0xff8800ff) };
        g.paint(&ink, 1.0);
        g.press(210.0, 170.0);
        assert_eq!(g.release(212.0, 171.0, 0, Instant::now()), Out::Station(s));
    }

    fn ink() -> Ink {
        Ink { sphere: Rgba::hex(0x101010ff), land: Rgba::hex(0x303030ff), grid: Rgba::hex(0x404040ff), outline: Rgba::hex(0x808080ff), signal: Rgba::hex(0xff8800ff), accent: Rgba::hex(0xff8800ff) }
    }

    /// A picture whose texel says where it is: red the longitude, green
    /// the latitude.
    fn coded_earth(width: usize, height: usize) -> Earth {
        let mut rgb = Vec::with_capacity(width * height * 3);
        for y in 0..height {
            for x in 0..width {
                rgb.extend([(x * 256 / width) as u8, (y * 256 / height) as u8, 128]);
            }
        }
        Earth::new(width, height, rgb)
    }

    fn picture(g: &mut Globe) -> (Bitmap, (f64, f64)) {
        let ops = g.paint(&ink(), 1.0);
        ops.iter().find_map(|op| if let VOp::Image(i, at, _) = op { Some((i.clone(), *at)) } else { None }).expect("an image op")
    }

    fn texel_at(g: &mut Globe, x: f64, y: f64) -> [u8; 4] {
        let (image, (ox, oy)) = picture(g);
        let p = image.pixmap.sample((x - ox) as u16, (y - oy) as u16);
        [p.r, p.g, p.b, p.a]
    }

    #[test]
    fn the_picture_lands_where_the_pose_points() {
        // Facing 0, 0 the disc's centre is the picture's centre; facing
        // 90 E it is three quarters across. The shade scales every channel
        // alike, so the red to green ratio reads the longitude.
        let mut g = Globe { rect: (0.0, 0.0, 400.0, 400.0), centre_latitude: 0.0, centre_longitude: 0.0, earth: Some(Arc::new(coded_earth(512, 256))), ..Globe::default() };
        let [r, gg, _, a] = texel_at(&mut g, 200.0, 200.0);
        assert_eq!(a, 255);
        assert!((r as f64 / gg as f64 - 1.0).abs() < 0.05, "{r} {gg}");
        g.centre_longitude = 90.0;
        let [r2, g2, ..] = texel_at(&mut g, 200.0, 200.0);
        assert!((r2 as f64 / g2 as f64 - 1.5).abs() < 0.05, "{r2} {g2}");
        // Up the screen is north: a smaller row, so a lower green to blue.
        let [_, north, b, _] = texel_at(&mut g, 200.0, 120.0);
        assert!((north as f64 / b as f64) < 0.9, "{north} {b}");
    }

    #[test]
    fn off_the_sphere_stays_clear() {
        let mut g = Globe { rect: (0.0, 0.0, 400.0, 400.0), earth: Some(Arc::new(coded_earth(64, 32))), ..Globe::default() };
        let (image, _) = picture(&mut g);
        assert_eq!(image.pixmap.sample(0, 0).a, 0, "the box's corner is off the disc");
        let (w, h) = (image.pixmap.width(), image.pixmap.height());
        assert_eq!(image.pixmap.sample(w / 2, h / 2).a, 255);
    }

    #[test]
    fn without_a_picture_the_flat_globe_draws() {
        let mut g = Globe { rect: (0.0, 0.0, 400.0, 400.0), ..Globe::default() };
        assert!(!g.paint(&ink(), 1.0).iter().any(|op| matches!(op, VOp::Image(..))));
    }

    #[test]
    fn fast_atan2_holds_a_tenth_of_a_texel() {
        let mut worst = 0.0f32;
        for i in 0..3600 {
            let a = (i as f32 / 10.0).to_radians() - std::f32::consts::PI;
            for m in [0.3f32, 1.0, 7.0] {
                let (y, x) = (a.sin() * m, a.cos() * m);
                let e = (fast_atan2(y, x) - y.atan2(x)).abs();
                worst = worst.max(e.min((e - std::f32::consts::TAU).abs()));
            }
        }
        assert!(worst < 1.5e-4, "{worst}");
    }

    #[test]
    fn sampling_a_full_disc() {
        // A 1000 px pane, the atlas's globe on a 2560x1440 output.
        let mut g = Globe {
            rect: (0.0, 0.0, 1000.0, 900.0),
            countries: Some(Arc::new(load())),
            earth: Some(Arc::new(coded_earth(4096, 2048))),
            ..Globe::default()
        };
        let t = Instant::now();
        for i in 0..20 {
            g.centre_longitude = i as f64 * 3.0;
            g.paint(&ink(), 1.0);
        }
        eprintln!("globe build with imagery: {} us a frame", t.elapsed().as_micros() / 20);
        let earth = g.earth.clone().unwrap();
        let rot = Rot { sin_lat: 0.3, cos_lat: 0.95, sin_lon: 0.5, cos_lon: 0.86 };
        let t = Instant::now();
        let mut px = 0;
        let mut pool = Vec::new();
        for _ in 0..20 {
            let b = earth.sample(&mut pool, false, (100, 50, 900, 850), (500.0, 450.0), 547.0, 396.0, rm::view_distance(1.0), &rot).unwrap();
            px = b.pixmap.width() as usize * b.pixmap.height() as usize;
        }
        eprintln!("sampler alone: {} us over {px} px", t.elapsed().as_micros() / 20);
        let t = Instant::now();
        for _ in 0..20 {
            earth.sample(&mut pool, true, (100, 50, 900, 850), (500.0, 450.0), 547.0, 396.0, rm::view_distance(1.0), &rot).unwrap();
        }
        eprintln!("sampler coarse: {} us", t.elapsed().as_micros() / 20);
        let b = earth.sample(&mut pool, true, (100, 50, 900, 850), (500.0, 450.0), 547.0, 396.0, rm::view_distance(1.0), &rot).unwrap();
        assert_eq!(b.pixmap.sample(400, 400), b.pixmap.sample(401, 401), "a coarse sample covers its 2x2 block");
        g.earth = None;
        let t = Instant::now();
        for i in 0..20 {
            g.centre_longitude = i as f64 * 3.0 + 1.0;
            g.paint(&ink(), 1.0);
        }
        eprintln!("globe build flat: {} us a frame", t.elapsed().as_micros() / 20);
    }

    fn dragged() -> Globe {
        Globe { rect: (0.0, 0.0, 400.0, 300.0), centre_latitude: 0.0, centre_longitude: 0.0, ..Globe::default() }
    }

    /// The coast's speed off a release, or None when it launched nothing.
    fn coast(g: &Globe) -> Option<f64> {
        g.kinetic.then(|| g.velocity.0.hypot(g.velocity.1))
    }

    #[test]
    fn a_drag_turns_the_globe_by_the_pointer_travel() {
        let mut g = dragged();
        let per_px = g.longitude_sensitivity();
        g.press(100.0, 150.0);
        for i in 1..=10u32 {
            g.motion(100.0 + 10.0 * f64::from(i), 150.0, Some(i * 16));
        }
        let want = -100.0 * per_px;
        assert!((g.centre_longitude - want).abs() < 1e-6, "{} vs {want}", g.centre_longitude);
    }

    #[test]
    fn a_pointer_that_stopped_before_release_does_not_coast() {
        let mut g = dragged();
        g.press(100.0, 150.0);
        for i in 1..=10u32 {
            g.motion(100.0 + 20.0 * f64::from(i), 150.0, Some(1000 + i * 8));
        }
        // Still for 60 ms, then let go: nothing carries, however fast the
        // drag was.
        g.release(300.0, 150.0, 1000 + 80 + 60, Instant::now());
        assert_eq!(coast(&g), None);
    }

    #[test]
    fn a_slow_tail_does_not_coast() {
        let mut g = dragged();
        g.press(100.0, 150.0);
        g.motion(112.0, 150.0, Some(0));
        g.motion(113.0, 150.0, Some(16));
        g.release(113.0, 150.0, 17, Instant::now());
        assert_eq!(coast(&g), None, "a 60 px/s tail started a coast");
    }

    #[test]
    fn coalesced_motion_does_not_read_as_a_flick() {
        // Three events the compositor stamped within a millisecond, all
        // handled in one loop turn: 30 px over the 16 ms floor at most.
        let mut g = dragged();
        g.press(100.0, 150.0);
        g.motion(115.0, 150.0, Some(500));
        g.motion(125.0, 150.0, Some(500));
        g.motion(145.0, 150.0, Some(501));
        g.release(145.0, 150.0, 501, Instant::now());
        let speed = coast(&g).expect("a moving release coasts");
        assert!(speed <= 30.0 / 0.016 + 1e-6, "{speed} px/s");
    }

    #[test]
    fn a_release_carries_only_the_recent_motion() {
        // A fast sweep, then 96 ms of crawling at 1 px a frame: the sweep is
        // past the window and the crawl is under the launch floor.
        let mut g = dragged();
        g.press(100.0, 150.0);
        g.motion(150.0, 150.0, Some(8));
        g.motion(250.0, 150.0, Some(16));
        for i in 1..=6u32 {
            g.motion(250.0 + f64::from(i), 150.0, Some(16 + i * 16));
        }
        g.release(256.0, 150.0, 16 + 96 + 4, Instant::now());
        assert_eq!(coast(&g), None);
    }

    #[test]
    fn a_moving_release_coasts_at_its_own_speed() {
        let mut g = dragged();
        g.press(100.0, 150.0);
        for i in 1..=10u32 {
            g.motion(100.0 + 8.0 * f64::from(i), 150.0, Some(i * 16));
        }
        g.release(180.0, 150.0, 164, Instant::now());
        let speed = coast(&g).expect("a moving release coasts");
        assert!((400.0..=500.0).contains(&speed), "{speed} px/s off a 500 px/s drag");
    }
}
