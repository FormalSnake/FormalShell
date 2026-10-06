//! App icons for windows (AppIconService.qml): which desktop entry a window
//! belongs to (`fs_system`'s class, process and title tiers), that entry's
//! icon through [`icons`], fitted to the size the cell draws. All
//! the filesystem and decode work runs on the blocking pool; the cell only
//! ever reads finished pixmaps off the store.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

use fs_system::compositor::appicon::{self, DesktopEntry, ProcInfo};

use super::icons;
use crate::runtime::Ctx;
use crate::scene::Bitmap;
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
    pub image: Option<Bitmap>,
}

impl PartialEq for Icon {
    fn eq(&self, other: &Self) -> bool {
        self.source == other.source
            && match (&self.image, &other.image) {
                (Some(a), Some(b)) => a.same_as(b),
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
    fitted: HashMap<(PathBuf, u32), Option<Bitmap>>,
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
        let Some(path) = icons::lookup(&entry.icon, "") else { return Icon::default() };
        let source = path.to_string_lossy().into_owned();
        let image = self.fitted.entry((path, size)).or_insert_with_key(|(p, s)| icons::load(p)?.bitmap(*s)).clone();
        Icon { source, image }
    }
}

fn window_of(q: &Query) -> appicon::Window {
    appicon::Window { app_id: q.app_id.clone(), initial_class: q.initial_class.clone(), initial_title: q.initial_title.clone() }
}

fn applications_dirs() -> Vec<PathBuf> {
    icons::data_dirs().into_iter().map(|d| d.join("applications")).collect()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_lines() {
        assert_eq!(split_exec("foot --app-id=x %U"), ["foot", "--app-id=x"]);
        assert_eq!(split_exec(r#"env "A B"=1 /usr/bin/app %%x"#), ["env", "A B=1", "/usr/bin/app", "%x"]);
        assert!(split_exec("").is_empty());
    }
}
