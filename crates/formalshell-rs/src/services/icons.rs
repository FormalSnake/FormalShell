//! Pictures other processes hand the shell: an icon by freedesktop name, a
//! raw pixmap or a PNG, decoded to straight-alpha RGBA on the pool and
//! scaled to a surface's own size (a few hundred pixels). Names resolve
//! through the configured icon theme's inheritance chain by the spec's size
//! distance, then through any other installed theme, then loose pixmaps.

use std::collections::HashMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use image::imageops::{self, FilterType};
use image::RgbaImage;

use crate::scene::Bitmap;

/// The longest side a decoded picture keeps.
const MAX: u32 = 64;

#[derive(Clone)]
pub struct Raw {
    pub width: u32,
    pub height: u32,
    pub rgba: Arc<Vec<u8>>,
}

impl PartialEq for Raw {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.rgba, &other.rgba)
    }
}

impl fmt::Debug for Raw {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Raw({}x{})", self.width, self.height)
    }
}

impl Raw {
    fn from_image(img: RgbaImage) -> Option<Self> {
        let (w, h) = img.dimensions();
        if w == 0 || h == 0 {
            return None;
        }
        let img = if w.max(h) > MAX {
            let s = MAX as f64 / w.max(h) as f64;
            let (nw, nh) = (((w as f64 * s).round() as u32).max(1), ((h as f64 * s).round() as u32).max(1));
            imageops::resize(&img, nw, nh, FilterType::Lanczos3)
        } else {
            img
        };
        let (width, height) = img.dimensions();
        Some(Self { width, height, rgba: Arc::new(img.into_raw()) })
    }

    /// Fitted inside a `size` square and centred in it, ready to draw.
    pub fn bitmap(&self, size: u32) -> Option<Bitmap> {
        let size = size.max(1);
        let src = RgbaImage::from_raw(self.width, self.height, self.rgba.as_ref().clone())?;
        let s = size as f64 / self.width.max(self.height) as f64;
        let (w, h) = (((self.width as f64 * s).round() as u32).clamp(1, size), ((self.height as f64 * s).round() as u32).clamp(1, size));
        let fitted = if (w, h) == (self.width, self.height) { src } else { imageops::resize(&src, w, h, FilterType::Triangle) };
        let mut canvas = RgbaImage::new(size, size);
        imageops::replace(&mut canvas, &fitted, ((size - w) / 2) as i64, ((size - h) / 2) as i64);
        Some(Bitmap::from_rgba(size as u16, size as u16, canvas.into_raw()))
    }
}

pub fn from_rgba(width: i32, height: i32, rgba: &[u8]) -> Option<Raw> {
    let img = RgbaImage::from_raw(u32::try_from(width).ok()?, u32::try_from(height).ok()?, rgba.to_vec())?;
    Raw::from_image(img)
}

pub fn from_bytes(bytes: &[u8]) -> Option<Raw> {
    Raw::from_image(image::load_from_memory(bytes).ok()?.to_rgba8())
}

fn from_svg(data: &[u8]) -> Option<Raw> {
    let tree = resvg::usvg::Tree::from_data(data, &resvg::usvg::Options::default()).ok()?;
    let size = tree.size();
    let scale = MAX as f32 / size.width().max(size.height());
    let (w, h) = ((size.width() * scale).round().max(1.0) as u32, (size.height() * scale).round().max(1.0) as u32);
    let mut pixmap = resvg::tiny_skia::Pixmap::new(w, h)?;
    resvg::render(&tree, resvg::tiny_skia::Transform::from_scale(scale, scale), &mut pixmap.as_mut());
    let mut rgba = pixmap.take();
    for px in rgba.chunks_exact_mut(4) {
        let a = px[3] as u32;
        if a > 0 && a < 255 {
            for c in &mut px[..3] {
                *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
            }
        }
    }
    Some(Raw { width: w, height: h, rgba: Arc::new(rgba) })
}

fn decode(path: &Path) -> Option<Raw> {
    let data = std::fs::read(path).ok()?;
    match path.extension().and_then(|e| e.to_str()) {
        Some("svg") => from_svg(&data),
        _ => from_bytes(&data),
    }
}

pub fn data_dirs() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let mut dirs = Vec::new();
    match std::env::var_os("XDG_DATA_HOME") {
        Some(d) if !d.is_empty() => dirs.push(PathBuf::from(d)),
        _ => dirs.extend(home.iter().map(|h| h.join(".local/share"))),
    }
    let system = std::env::var("XDG_DATA_DIRS").unwrap_or_default();
    if system.is_empty() {
        dirs.extend(["/usr/local/share", "/usr/share"].map(PathBuf::from));
    } else {
        dirs.extend(system.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
    }
    dirs.extend(home.iter().map(|h| h.join(".nix-profile/share")));
    dirs.push(PathBuf::from("/run/current-system/sw/share"));
    let mut seen = std::collections::HashSet::new();
    dirs.retain(|d| seen.insert(d.clone()));
    dirs
}

/// How well a size directory suits `MAX`: scalable first, then the nearest
/// size above it, then the nearest below.
fn rank(dir: &str) -> u32 {
    if dir == "scalable" {
        return 0;
    }
    match dir.split('x').next().and_then(|n| n.parse::<u32>().ok()) {
        Some(n) if n >= MAX => n - MAX + 1,
        Some(n) => 10_000 + (MAX - n),
        None => 100_000,
    }
}

fn subdirs(dir: &Path) -> Vec<(String, PathBuf)> {
    let Ok(read) = std::fs::read_dir(dir) else { return Vec::new() };
    read.filter_map(Result::ok)
        .filter(|e| e.path().is_dir())
        .filter_map(|e| Some((e.file_name().into_string().ok()?, e.path())))
        .collect()
}

fn file_in(dir: &Path, name: &str) -> Option<PathBuf> {
    ["svg", "png"].iter().map(|ext| dir.join(format!("{name}.{ext}"))).find(|p| p.is_file())
}

/// The best file for `name` inside one theme directory, in either layout:
/// `<size>/<context>/` or `<context>/<size>/`.
fn in_theme(theme: &Path, name: &str) -> Option<PathBuf> {
    let mut best: Option<(u32, PathBuf)> = None;
    let mut consider = |score: u32, path: PathBuf| {
        if best.as_ref().is_none_or(|(s, _)| score < *s) {
            best = Some((score, path));
        }
    };
    if let Some(p) = file_in(theme, name) {
        consider(50_000, p);
    }
    for (first, first_path) in subdirs(theme) {
        if let Some(p) = file_in(&first_path, name) {
            consider(rank(&first), p);
        }
        for (second, second_path) in subdirs(&first_path) {
            if let Some(p) = file_in(&second_path, name) {
                consider(rank(&first).min(rank(&second)), p);
            }
        }
    }
    best.map(|(_, p)| p)
}

/// An icon name (or an absolute path, or a `file://` URL) as a file: the
/// app's own theme path first, then the theme chain, then every other
/// installed theme, then the loose pixmaps.
pub fn lookup(name: &str, theme_path: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    if let Some(path) = name.strip_prefix("file://").or_else(|| Path::new(name).is_absolute().then_some(name)) {
        return Path::new(path).is_file().then(|| PathBuf::from(path));
    }
    if !theme_path.is_empty() {
        if let Some(p) = in_theme(Path::new(theme_path), name) {
            return Some(p);
        }
    }
    static THEMES: OnceLock<Mutex<Themes>> = OnceLock::new();
    let chained = THEMES.get_or_init(Default::default).lock().unwrap().find(name, MAX);
    if chained.is_some() {
        return chained;
    }
    let dirs = data_dirs();
    let mut themes: Vec<PathBuf> = Vec::new();
    for d in &dirs {
        let mut found: Vec<PathBuf> = subdirs(&d.join("icons")).into_iter().map(|(_, p)| p).collect();
        found.sort();
        themes.extend(found);
    }
    themes.iter().find_map(|t| in_theme(t, name)).or_else(|| dirs.iter().find_map(|d| file_in(&d.join("pixmaps"), name)))
}

/// A file decoded once per process.
pub fn load(path: &Path) -> Option<Raw> {
    static CACHE: OnceLock<Mutex<HashMap<PathBuf, Option<Raw>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(Default::default);
    if let Some(hit) = cache.lock().unwrap().get(path) {
        return hit.clone();
    }
    let raw = decode(path);
    cache.lock().unwrap().insert(path.to_owned(), raw.clone());
    raw
}

pub fn named(name: &str, theme_path: &str) -> Option<Raw> {
    load(&lookup(name, theme_path)?)
}

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Fixed,
    Scalable,
    Threshold,
}

struct Dir {
    path: String,
    size: u32,
    scale: u32,
    min: u32,
    max: u32,
    threshold: u32,
    kind: Kind,
}

impl Dir {
    /// The freedesktop spec's DirectorySizeDistance.
    fn distance(&self, size: u32) -> u32 {
        let want = size as i64;
        let (s, k) = (self.size as i64 * self.scale as i64, self.scale as i64);
        match self.kind {
            Kind::Fixed => (s - want).unsigned_abs() as u32,
            Kind::Scalable => {
                let (lo, hi) = (self.min as i64 * k, self.max as i64 * k);
                if want < lo { (lo - want) as u32 } else if want > hi { (want - hi) as u32 } else { 0 }
            }
            Kind::Threshold => {
                let (lo, hi) = ((self.size as i64 - self.threshold as i64) * k, (self.size as i64 + self.threshold as i64) * k);
                if want < lo { (lo - want) as u32 } else if want > hi { (want - hi) as u32 } else { 0 }
            }
        }
    }
}

struct Theme {
    inherits: Vec<String>,
    dirs: Vec<Dir>,
    /// Each base directory this theme has a folder in.
    roots: Vec<PathBuf>,
}

#[derive(Default)]
struct Themes {
    loaded: HashMap<String, Option<Theme>>,
    chain: Option<Vec<String>>,
}

fn icon_bases() -> Vec<PathBuf> {
    let mut bases = vec![home().join(".icons")];
    bases.extend(data_dirs().into_iter().map(|d| d.join("icons")));
    bases
}

/// The theme the GTK settings name, hicolor when none does.
fn configured_theme() -> String {
    let config = std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()).map_or_else(|| home().join(".config"), PathBuf::from);
    let settings = std::fs::read_to_string(config.join("gtk-3.0/settings.ini")).unwrap_or_default();
    settings
        .lines()
        .find_map(|l| l.trim().strip_prefix("gtk-icon-theme-name").and_then(|r| r.trim_start().strip_prefix('=')))
        .map(|v| v.trim().to_owned())
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "hicolor".into())
}

fn load_theme(name: &str) -> Option<Theme> {
    let roots: Vec<PathBuf> = icon_bases().into_iter().map(|b| b.join(name)).filter(|r| r.is_dir()).collect();
    let index = roots.iter().find_map(|r| std::fs::read_to_string(r.join("index.theme")).ok())?;
    let mut sections: Vec<(String, HashMap<String, String>)> = Vec::new();
    for line in index.lines() {
        let line = line.trim();
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            sections.push((name.to_owned(), HashMap::new()));
        } else if let (Some((k, v)), Some((_, fields))) = (line.split_once('='), sections.last_mut()) {
            fields.entry(k.trim().to_owned()).or_insert_with(|| v.trim().to_owned());
        }
    }
    let list = |s: &HashMap<String, String>, k: &str| -> Vec<String> {
        s.get(k).map(|v| v.split(',').map(|p| p.trim().to_owned()).filter(|p| !p.is_empty()).collect()).unwrap_or_default()
    };
    let head = sections.iter().find(|(n, _)| n == "Icon Theme").map(|(_, f)| f)?;
    let num = |s: &HashMap<String, String>, k: &str, default: u32| s.get(k).and_then(|v| v.parse().ok()).unwrap_or(default);
    let dirs = list(head, "Directories")
        .into_iter()
        .filter_map(|path| {
            let fields = &sections.iter().find(|(n, _)| *n == path)?.1;
            let size = num(fields, "Size", 0);
            let kind = match fields.get("Type").map(String::as_str) {
                Some("Fixed") => Kind::Fixed,
                Some("Scalable") => Kind::Scalable,
                _ => Kind::Threshold,
            };
            Some(Dir {
                size,
                scale: num(fields, "Scale", 1).max(1),
                min: num(fields, "MinSize", size),
                max: num(fields, "MaxSize", size),
                threshold: num(fields, "Threshold", 2),
                kind,
                path,
            })
        })
        .collect();
    Some(Theme { inherits: list(head, "Inherits"), dirs, roots })
}

impl Themes {
    fn theme(&mut self, name: &str) -> Option<&Theme> {
        self.loaded.entry(name.to_owned()).or_insert_with(|| load_theme(name)).as_ref()
    }

    /// The configured theme, what it inherits depth first, then hicolor.
    fn order(&mut self) -> Vec<String> {
        if let Some(c) = &self.chain {
            return c.clone();
        }
        let mut order: Vec<String> = Vec::new();
        let mut stack = vec![configured_theme()];
        while let Some(name) = stack.pop() {
            if order.contains(&name) {
                continue;
            }
            if let Some(t) = self.theme(&name) {
                stack.extend(t.inherits.iter().rev().cloned());
            }
            order.push(name);
        }
        if !order.iter().any(|n| n == "hicolor") {
            order.push("hicolor".into());
        }
        self.chain = Some(order.clone());
        order
    }

    fn find(&mut self, name: &str, size: u32) -> Option<PathBuf> {
        for theme in self.order() {
            let Some(t) = self.theme(&theme) else { continue };
            let mut best: Option<(u32, PathBuf)> = None;
            for dir in &t.dirs {
                for root in &t.roots {
                    for ext in ["png", "svg"] {
                        let path = root.join(&dir.path).join(format!("{name}.{ext}"));
                        if !path.is_file() {
                            continue;
                        }
                        let d = dir.distance(size);
                        if best.as_ref().is_none_or(|(b, _)| d < *b) {
                            best = Some((d, path));
                        }
                    }
                }
            }
            if let Some((_, path)) = best {
                return Some(path);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_rank_scalable_then_nearest_above() {
        assert!(rank("scalable") < rank("64x64"));
        assert!(rank("64x64") < rank("128x128"));
        assert!(rank("128x128") < rank("48x48"));
        assert!(rank("48x48") < rank("16x16"));
    }

    #[test]
    fn size_distance() {
        let fixed = Dir { path: "48x48/apps".into(), size: 48, scale: 1, min: 48, max: 48, threshold: 2, kind: Kind::Fixed };
        assert_eq!(fixed.distance(20), 28);
        let svg = Dir { path: "scalable/apps".into(), size: 128, scale: 1, min: 8, max: 512, threshold: 2, kind: Kind::Scalable };
        assert_eq!(svg.distance(20), 0);
        let thr = Dir { path: "32x32".into(), size: 32, scale: 1, min: 32, max: 32, threshold: 2, kind: Kind::Threshold };
        assert_eq!(thr.distance(33), 0);
        assert_eq!(thr.distance(40), 6);
    }

    #[test]
    fn a_pixmap_fits_its_square() {
        let raw = from_rgba(2, 1, &[255, 0, 0, 255, 0, 255, 0, 255]).unwrap();
        let b = raw.bitmap(4).unwrap();
        assert_eq!((b.pixmap.width(), b.pixmap.height()), (4, 4));
    }

    #[test]
    fn svg_renders_at_the_longest_side() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="8"><rect width="16" height="8" fill="#f00"/></svg>"##;
        let raw = from_svg(svg).unwrap();
        assert_eq!((raw.width, raw.height), (MAX, MAX / 2));
        assert_eq!(&raw.rgba[..4], &[255, 0, 0, 255]);
    }
}
