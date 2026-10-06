//! Pictures other processes hand the shell: an icon by freedesktop name, a
//! raw pixmap or a PNG, decoded to straight-alpha RGBA on the pool and
//! scaled to a surface's own size on the UI thread (a few hundred pixels).

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

fn load(path: &Path) -> Option<Raw> {
    let data = std::fs::read(path).ok()?;
    match path.extension().and_then(|e| e.to_str()) {
        Some("svg") => from_svg(&data),
        _ => from_bytes(&data),
    }
}

fn data_dirs() -> Vec<PathBuf> {
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

fn find(name: &str, theme_path: &str) -> Option<PathBuf> {
    if Path::new(name).is_absolute() {
        return Path::new(name).is_file().then(|| PathBuf::from(name));
    }
    if !theme_path.is_empty() {
        if let Some(p) = in_theme(Path::new(theme_path), name) {
            return Some(p);
        }
    }
    let dirs = data_dirs();
    let mut themes: Vec<PathBuf> = Vec::new();
    for d in &dirs {
        let icons = d.join("icons");
        let mut found: Vec<PathBuf> = subdirs(&icons).into_iter().map(|(_, p)| p).collect();
        found.sort();
        themes.extend(found);
    }
    // hicolor is the spec's fallback every theme inherits, so it goes first:
    // an app's own icon lives there.
    themes.sort_by_key(|p| p.file_name().is_none_or(|n| n != "hicolor"));
    themes.iter().find_map(|t| in_theme(t, name)).or_else(|| dirs.iter().find_map(|d| file_in(&d.join("pixmaps"), name)))
}

pub fn named(name: &str, theme_path: &str) -> Option<Raw> {
    static CACHE: OnceLock<Mutex<HashMap<(String, String), Option<Raw>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(Default::default);
    let key = (name.to_owned(), theme_path.to_owned());
    if let Some(hit) = cache.lock().unwrap().get(&key) {
        return hit.clone();
    }
    let raw = find(name, theme_path).and_then(|p| load(&p));
    cache.lock().unwrap().insert(key, raw.clone());
    raw
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
