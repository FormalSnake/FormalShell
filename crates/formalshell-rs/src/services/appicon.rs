//! App icons for windows (AppIconService.qml): which desktop entry a window
//! belongs to (`fs_system`'s class, process and title tiers), that entry's
//! icon through the XDG icon theme, decoded to the size the cell draws. All
//! the filesystem and decode work runs on the blocking pool; the cell only
//! ever reads finished pixmaps off the store.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

use fs_system::compositor::appicon::{self, DesktopEntry, ProcInfo};
use vello_cpu::Pixmap;

use crate::runtime::Ctx;
use crate::store;

/// What the cell asks about one window.
#[derive(Clone, Debug, PartialEq)]
pub struct Query {
    pub id: String,
    pub app_id: String,
    pub initial_class: String,
    pub initial_title: String,
    pub pid: i64,
}

/// One window's answer. `source` is empty when no entry or no theme icon
/// answered, which is the cell's cue for the generic window mark.
#[derive(Clone, Debug, Default)]
pub struct Icon {
    pub source: String,
    pub image: Option<Arc<Pixmap>>,
}

impl PartialEq for Icon {
    fn eq(&self, other: &Self) -> bool {
        self.source == other.source
            && match (&self.image, &other.image) {
                (Some(a), Some(b)) => Arc::ptr_eq(a, b),
                (None, None) => true,
                _ => false,
            }
    }
}

#[derive(Default)]
pub struct State {
    pub by_window: HashMap<String, Icon>,
}

pub struct Diff(pub Vec<(String, Icon)>);

impl State {
    pub fn apply(&mut self, Diff(icons): Diff) -> bool {
        let mut changed = false;
        for (id, icon) in icons {
            if self.by_window.get(&id) != Some(&icon) {
                self.by_window.insert(id, icon);
                changed = true;
            }
        }
        changed
    }
}

static PROBE: OnceLock<async_channel::Sender<(u32, Vec<Query>)>> = OnceLock::new();

/// Resolves `queries` to icons drawn `size` pixels square.
pub fn probe(size: u32, queries: Vec<Query>) {
    if let Some(tx) = PROBE.get() {
        let _ = tx.try_send((size, queries));
    }
}

pub async fn run(ctx: Ctx) {
    let (tx, rx) = async_channel::unbounded();
    let _ = PROBE.set(tx);
    let inner = Arc::new(Mutex::new(Inner::default()));
    while let Ok((mut size, mut queries)) = rx.recv().await {
        // Only the newest ask matters when several queue up.
        while let Ok(next) = rx.try_recv() {
            (size, queries) = next;
        }
        let inner = inner.clone();
        let done = ctx.pool().run(move || inner.lock().unwrap().resolve(size, &queries)).await;
        if let Some(icons) = done {
            ctx.publish(store::Diff::AppIcon(Diff(icons)));
        }
    }
}

#[derive(Default)]
struct Inner {
    entries: Vec<DesktopEntry>,
    stamp: Vec<Option<SystemTime>>,
    scanned: bool,
    procs: HashMap<String, Vec<ProcInfo>>,
    asked: HashSet<i64>,
    themes: Themes,
    decoded: HashMap<(String, u32), Option<Arc<Pixmap>>>,
}

impl Inner {
    fn resolve(&mut self, size: u32, queries: &[Query]) -> Vec<(String, Icon)> {
        self.rescan();
        self.read_procs(queries);
        queries.iter().map(|q| (q.id.clone(), self.icon_for(size, q))).collect()
    }

    /// Entries are rescanned when any applications directory's mtime moved,
    /// which is what an install under a running shell does.
    fn rescan(&mut self) {
        let dirs = applications_dirs();
        let stamp: Vec<Option<SystemTime>> = dirs.iter().map(|d| std::fs::metadata(d).and_then(|m| m.modified()).ok()).collect();
        if self.scanned && stamp == self.stamp {
            return;
        }
        self.entries = scan_entries(&dirs);
        self.stamp = stamp;
        self.scanned = true;
    }

    /// `/proc` once per window pid that no entry claims by class.
    fn read_procs(&mut self, queries: &[Query]) {
        let mut wanted: Vec<String> = Vec::new();
        for q in queries {
            let win = window_of(q);
            if q.pid > 1 && !self.asked.contains(&q.pid) && appicon::by_class(Some(&win), &self.entries).is_none() {
                self.asked.insert(q.pid);
                wanted.push(q.pid.to_string());
            }
        }
        if wanted.is_empty() {
            return;
        }
        let argv = appicon::proc_command(&wanted);
        let Ok(out) = std::process::Command::new(&argv[0]).args(&argv[1..]).output() else { return };
        self.procs.extend(appicon::parse_procs(&String::from_utf8_lossy(&out.stdout)));
    }

    fn icon_for(&mut self, size: u32, q: &Query) -> Icon {
        let win = window_of(q);
        let procs = self.procs.get(&q.pid.to_string()).map(Vec::as_slice);
        let Some(entry) = appicon::entry_for(Some(&win), &self.entries, procs) else { return Icon::default() };
        let name = entry.icon.clone();
        let Some(path) = self.themes.find(&name, size) else { return Icon::default() };
        let source = path.to_string_lossy().into_owned();
        let key = (source.clone(), size);
        let image = self.decoded.entry(key).or_insert_with(|| decode(&path, size).map(Arc::new)).clone();
        Icon { source, image }
    }
}

fn window_of(q: &Query) -> appicon::Window {
    appicon::Window { app_id: q.app_id.clone(), initial_class: q.initial_class.clone(), initial_title: q.initial_title.clone() }
}

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

fn data_home() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()).map_or_else(|| home().join(".local/share"), PathBuf::from)
}

fn data_dirs() -> Vec<PathBuf> {
    let dirs = std::env::var("XDG_DATA_DIRS").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    let mut all = vec![data_home()];
    all.extend(dirs.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
    all
}

fn applications_dirs() -> Vec<PathBuf> {
    data_dirs().into_iter().map(|d| d.join("applications")).collect()
}

// ---- desktop entries --------------------------------------------------------

/// Every launchable entry, a higher-priority directory shadowing a lower one's
/// entry of the same id.
fn scan_entries(dirs: &[PathBuf]) -> Vec<DesktopEntry> {
    let mut seen: HashSet<String> = HashSet::new();
    let mut out = Vec::new();
    for dir in dirs {
        let mut files = Vec::new();
        collect(dir, dir, &mut files);
        files.sort();
        for (id, path) in files {
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some(entry) = parse_entry(&id, &path) {
                out.push(entry);
            }
        }
    }
    out
}

fn collect(root: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) {
    let Ok(read) = std::fs::read_dir(dir) else { return };
    for item in read.flatten() {
        let path = item.path();
        if path.is_dir() {
            collect(root, &path, out);
        } else if path.extension().is_some_and(|e| e == "desktop") {
            let rel = path.strip_prefix(root).unwrap_or(&path).with_extension("");
            out.push((rel.to_string_lossy().replace('/', "-"), path));
        }
    }
}

fn parse_entry(id: &str, path: &Path) -> Option<DesktopEntry> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    let mut fields: HashMap<&str, &str> = HashMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
        } else if in_entry && !line.starts_with('#') {
            if let Some((k, v)) = line.split_once('=') {
                fields.entry(k.trim()).or_insert_with(|| v.trim());
            }
        }
    }
    let flag = |k: &str| fields.get(k) == Some(&"true");
    if fields.get("Type").is_some_and(|t| *t != "Application") || flag("NoDisplay") || flag("Hidden") {
        return None;
    }
    let text = |k: &str| fields.get(k).copied().unwrap_or_default().to_owned();
    Some(DesktopEntry {
        id: id.to_owned(),
        name: text("Name"),
        startup_class: text("StartupWMClass"),
        icon: text("Icon"),
        command: split_exec(fields.get("Exec").copied().unwrap_or_default()),
    })
}

/// An `Exec` line as an argv: quotes and backslashes honoured, field codes
/// (`%f`, `%U`, ...) dropped, `%%` a percent.
fn split_exec(exec: &str) -> Vec<String> {
    let mut args: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut live = false;
    let mut quote: Option<char> = None;
    let mut chars = exec.chars().peekable();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some(_), '\\') => {
                if let Some(n) = chars.next() {
                    cur.push(n);
                }
            }
            (Some(_), c) => cur.push(c),
            (None, '"' | '\'') => {
                quote = Some(c);
                live = true;
            }
            (None, '\\') => {
                if let Some(n) = chars.next() {
                    cur.push(n);
                    live = true;
                }
            }
            (None, c) if c.is_whitespace() => {
                if live || !cur.is_empty() {
                    args.push(std::mem::take(&mut cur));
                    live = false;
                }
            }
            (None, '%') => match chars.next() {
                Some('%') => {
                    cur.push('%');
                    live = true;
                }
                _ => {}
            },
            (None, c) => {
                cur.push(c);
                live = true;
            }
        }
    }
    if live || !cur.is_empty() {
        args.push(cur);
    }
    args.retain(|a| !a.is_empty());
    args
}

// ---- icon theme -------------------------------------------------------------

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

    /// An `Icon=` value as a file: an absolute path as it is, a name through
    /// the theme chain by size distance, then the loose pixmaps.
    fn find(&mut self, name: &str, size: u32) -> Option<PathBuf> {
        if name.is_empty() {
            return None;
        }
        if let Some(path) = name.strip_prefix("file://").or_else(|| name.starts_with('/').then_some(name)) {
            return Path::new(path).is_file().then(|| PathBuf::from(path));
        }
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
        data_dirs()
            .into_iter()
            .map(|d| d.join("pixmaps"))
            .flat_map(|d| ["png", "svg"].map(|e| d.join(format!("{name}.{e}"))))
            .find(|p| p.is_file())
    }
}

// ---- decode -----------------------------------------------------------------

/// The file drawn to fit a `size` square, aspect kept, as premultiplied
/// pixels.
fn decode(path: &Path, size: u32) -> Option<Pixmap> {
    let bytes = std::fs::read(path).ok()?;
    let side = u16::try_from(size).ok()?.max(1);
    let rgba = if path.extension().is_some_and(|e| e == "svg") { rasterise(&bytes, size)? } else { raster(&bytes, size)? };
    let mut pixmap = Pixmap::new(side, side);
    pixmap.data_as_u8_slice_mut().copy_from_slice(&rgba);
    Some(pixmap)
}

fn rasterise(bytes: &[u8], size: u32) -> Option<Vec<u8>> {
    use resvg::{tiny_skia, usvg};
    let tree = usvg::Tree::from_data(bytes, &usvg::Options::default()).ok()?;
    let (w, h) = (tree.size().width(), tree.size().height());
    if w <= 0.0 || h <= 0.0 {
        return None;
    }
    let scale = (size as f32 / w).min(size as f32 / h);
    let (dx, dy) = ((size as f32 - w * scale) / 2.0, (size as f32 - h * scale) / 2.0);
    let mut pixmap = tiny_skia::Pixmap::new(size, size)?;
    resvg::render(&tree, tiny_skia::Transform::from_scale(scale, scale).post_translate(dx, dy), &mut pixmap.as_mut());
    Some(pixmap.take())
}

fn raster(bytes: &[u8], size: u32) -> Option<Vec<u8>> {
    let image = image::load_from_memory(bytes).ok()?;
    let fitted = image.resize(size, size, image::imageops::FilterType::Lanczos3).to_rgba8();
    let mut canvas = image::RgbaImage::new(size, size);
    let (x, y) = ((size - fitted.width()) / 2, (size - fitted.height()) / 2);
    image::imageops::replace(&mut canvas, &fitted, x as i64, y as i64);
    let mut data = canvas.into_raw();
    for px in data.chunks_exact_mut(4) {
        let a = px[3] as u32;
        for c in &mut px[..3] {
            *c = ((*c as u32 * a + 127) / 255) as u8;
        }
    }
    Some(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_lines() {
        assert_eq!(split_exec("foot --app-id=x %U"), ["foot", "--app-id=x"]);
        assert_eq!(split_exec(r#"env "A B"=1 /usr/bin/app %%x"#), ["env", "A B=1", "/usr/bin/app", "%x"]);
        assert!(split_exec("").is_empty());
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
    fn decodes_a_png_square_and_fitted() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("flat.png");
        let mut img = image::RgbaImage::new(48, 24);
        for p in img.pixels_mut() {
            *p = image::Rgba([200, 0, 0, 255]);
        }
        img.save(&path).unwrap();
        let pixmap = decode(&path, 20).unwrap();
        assert_eq!((pixmap.width(), pixmap.height()), (20, 20));
        let mid = pixmap.data()[10 * 20 + 10];
        assert_eq!((mid.r, mid.a), (200, 255));
        assert_eq!(pixmap.data()[0].a, 0);
    }
}
