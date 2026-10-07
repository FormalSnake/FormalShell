// Portions from omarchy-radio-atlas (MIT, Copyright 2026 Akshar Patel)

//! Globe.qml: the globe in near-side perspective, countries off Natural
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
use vello_cpu::kurbo::{self, BezPath, Circle, Shape as _};

use crate::scene::{Brush, VOp};

const COUNTRIES: &str = include_str!("../../../../../shell/Radio/countries.json");

pub const HIT_RADIUS: f64 = 12.0;
const MINIMUM_SCALE: f64 = 0.72;
const MAXIMUM_SCALE: f64 = 24.0;
const LAUNCH_SPEED: f64 = 120.0;
const MAXIMUM_SPEED: f64 = 2400.0;
const DECELERATION: f64 = 1800.0;
const MAXIMUM_FRAME_TIME: f64 = 0.1;
const MAXIMUM_SAMPLE_AGE_MS: f64 = 100.0;
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

/// The palette the globe paints in, Globe.qml's colour properties.
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
    velocity: (f64, f64),
    velocity_at: Option<Instant>,
    sample: (f64, f64),
    sample_at: Option<Instant>,
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
}

pub struct Globe {
    pub countries: Option<Arc<Countries>>,
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

    /// The cursor shape Globe.qml's HoverHandler asks for.
    pub fn grabbing(&self) -> bool {
        self.drag.press.is_some()
    }

    pub fn over_station(&self) -> bool {
        self.hovered.is_some()
    }

    /// The pointer moved over the globe, in surface coordinates.
    pub fn motion(&mut self, x: f64, y: f64, now: Instant) -> Out {
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
                self.drag.velocity = (0.0, 0.0);
                self.drag.velocity_at = None;
                self.drag.sample = (px, py);
                self.drag.sample_at = Some(now);
            }
            self.sample(lx, ly, now);
            let (dx, dy) = (lx - self.drag.last.0, ly - self.drag.last.1);
            self.drag.last = (lx, ly);
            self.rotate_by(dx, dy);
            return Out::Interaction;
        }
        self.hovered = if self.kinetic { None } else { self.station_under(lx, ly).cloned() };
        Out::None
    }

    // Qt's filtered velocity can fall below the launch floor before
    // release, so a short sample of the latest movement stands beside it.
    fn sample(&mut self, x: f64, y: f64, now: Instant) {
        let Some(at) = self.drag.sample_at else { return };
        let ms = now.saturating_duration_since(at).as_secs_f64() * 1000.0;
        if ms <= 0.0 {
            return;
        }
        let (dx, dy) = (x - self.drag.sample.0, y - self.drag.sample.1);
        self.drag.sample = (x, y);
        self.drag.sample_at = Some(now);
        if ms > 250.0 {
            return;
        }
        let (vx, vy) = (dx * 1000.0 / ms, dy * 1000.0 / ms);
        if !vx.is_finite() || !vy.is_finite() {
            return;
        }
        self.drag.velocity = if self.drag.velocity_at.is_some() {
            (self.drag.velocity.0 * 0.25 + vx * 0.75, self.drag.velocity.1 * 0.25 + vy * 0.75)
        } else {
            (vx, vy)
        };
        self.drag.velocity_at = Some(now);
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

    pub fn release(&mut self, x: f64, y: f64, now: Instant) -> Out {
        let (lx, ly) = self.local(x, y);
        let drag = std::mem::take(&mut self.drag);
        if drag.press.is_none() {
            return Out::None;
        }
        if drag.active {
            let age = drag.velocity_at.map_or(f64::INFINITY, |t| now.saturating_duration_since(t).as_secs_f64() * 1000.0);
            let v = rm::kinetic_release_velocity((0.0, 0.0), drag.velocity, age, MAXIMUM_SAMPLE_AGE_MS);
            self.start(v.x, v.y, now);
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

    fn build(&mut self, ink: &Ink, alpha: f32) -> Vec<VOp> {
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
        ops.push(VOp::Fill(circle(disc), Brush::Radial { centre: lit, r0: disc * 0.05, r1: disc * 2.1, stops }));

        ops.push(VOp::Clip(circle(disc - 0.5)));
        let (lat, lon) = (self.centre_latitude * PI / 180.0, self.centre_longitude * PI / 180.0);
        let rot = Rot { sin_lat: lat.sin(), cos_lat: lat.cos(), sin_lon: lon.sin(), cos_lon: lon.cos() };
        let horizon = 1.0 / distance;
        let k = |depth: f64| r * (distance - 1.0) / (distance - depth);

        // The graticule, each segment thinning and fading toward the limb.
        let base = (r / 500.0).clamp(0.7, 1.5);
        let grid_ink = with_alpha(ink.grid, 0.3);
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
                    let fill = if is_active {
                        mix(ink.sphere, ink.accent, 0.25 + shade * 0.35, 0.9)
                    } else {
                        mix(land_dark, land_lit, 0.12 + shade * 0.88, 0.97)
                    };
                    let stroke = if is_active { with_alpha(ink.accent, 0.95) } else { with_alpha(ink.outline, 0.12 + near * 0.3) };
                    let width = if is_active { 1.5 } else { 0.35 + near * 0.55 };
                    let projected: Vec<[f64; 3]> = ring.world.iter().map(|p| rot.apply(p)).collect();
                    let screen = |p: &[f64; 3]| (cx + p[0] * k(p[2]), cy - p[1] * k(p[2]));
                    let Some(hidden) = projected.iter().position(|p| p[2] < horizon) else {
                        let mut path = BezPath::new();
                        for (i, p) in projected.iter().enumerate() {
                            if i == 0 { path.move_to(screen(p)) } else { path.line_to(screen(p)) }
                        }
                        path.close_path();
                        ops.push(VOp::Fill(path.clone(), solid(fill)));
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
                            ops.push(VOp::Fill(p, solid(fill)));
                        }
                        prev = cur;
                    }
                }
            }
        }

        // Limb darkening over the last stretch before the horizon.
        let shade = darker(ink.sphere, 3.0);
        let limb = vec![(0.0, fade(with_alpha(shade, 0.0))), (0.85, fade(with_alpha(shade, 0.0))), (1.0, fade(with_alpha(shade, 0.55)))];
        let square = kurbo::Rect::new(cx - disc, cy - disc, cx + disc, cy + disc).to_path(0.1);
        ops.push(VOp::Fill(square, Brush::Radial { centre: (cx, cy), r0: 0.0, r1: disc, stops: limb }));

        self.paint_signals(&mut ops, ink, alpha, &rot, (cx, cy));
        ops.push(VOp::Pop);

        // The atmosphere: a thin rim of the accent just outside the horizon.
        let rim = r * 0.04;
        let stops = vec![(0.0, fade(with_alpha(ink.accent, 0.35))), (1.0, fade(with_alpha(ink.accent, 0.0)))];
        ops.push(VOp::Stroke(circle(disc + rim / 2.0), Brush::Radial { centre: (cx, cy), r0: disc, r1: disc + rim, stops }, rim));
        ops.push(VOp::Stroke(circle(disc), solid(with_alpha(ink.outline, 0.3)), 1.0));
        ops.push(VOp::Pop);
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
            ops.push(VOp::Fill(Circle::new(at, radius).to_path(0.1), Brush::Solid(fade(c))));
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
        let now = Instant::now();
        g.press(210.0, 170.0);
        assert_eq!(g.release(212.0, 171.0, now), Out::Station(s));
    }
}
