//! What the shell reads out of mango's own config, which no IPC answer
//! carries: the binds for the launcher's keybinds route and the layout list
//! for the keyboard cell. Walked the way src/config/load.c parses it at
//! 0.18.0: `source=` and `source_optional=` files in place, `var=` values
//! expanded as `$name` and `${name}`, `key_mode=` naming the binds' mode.
//! A TOML config is not read.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use fs_menu::keybinds::{self, Bind};

/// mango's own lookup with no `-c`: `$HOME/.config/mango/config.conf`, then
/// the system one. It does not consult XDG_CONFIG_HOME.
pub fn entry(home: &Path) -> Option<PathBuf> {
    [home.join(".config/mango/config.conf"), PathBuf::from("/etc/mango/config.conf")].into_iter().find(|p| p.is_file())
}

#[derive(Debug, Default, PartialEq)]
pub struct Read {
    pub binds: Vec<Bind>,
    /// `xkb_rules_layout`, split on commas.
    pub layouts: Vec<String>,
}

struct Walk<'a> {
    read: &'a dyn Fn(&Path) -> Option<String>,
    home: PathBuf,
    dir: PathBuf,
    vars: HashMap<String, String>,
    key_mode: String,
    out: Read,
    /// The files being read, outermost first.
    stack: Vec<PathBuf>,
}

/// `#` starts a comment when whitespace comes before it outside quotes.
fn strip_comment(line: &str) -> &str {
    let mut quote = None;
    let mut prev_space = false;
    for (i, c) in line.char_indices() {
        match quote {
            Some(q) if c == q => quote = None,
            Some(_) => {}
            None if c == '\'' || c == '"' => quote = Some(c),
            None if c == '#' && i > 0 && prev_space => return &line[..i],
            None => {}
        }
        prev_space = c.is_whitespace();
    }
    line
}

fn expand(value: &str, vars: &HashMap<String, String>) -> String {
    let mut out = String::new();
    let mut rest = value;
    while let Some(at) = rest.find('$') {
        out.push_str(&rest[..at]);
        let tail = &rest[at + 1..];
        let found = match tail.strip_prefix('{') {
            Some(braced) => braced.find('}').map(|close| (&braced[..close], &braced[close + 1..])),
            None => {
                let end = tail.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).unwrap_or(tail.len());
                tail.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_').then(|| (&tail[..end], &tail[end..]))
            }
        };
        match found {
            Some((name, after)) if !name.is_empty() => {
                match vars.get(name) {
                    Some(v) => out.push_str(v),
                    None => out.push_str(&rest[at..rest.len() - after.len()]),
                }
                rest = after;
            }
            _ => {
                out.push('$');
                rest = tail;
            }
        }
    }
    out.push_str(rest);
    out
}

impl Walk<'_> {
    fn resolve(&self, path: &str) -> PathBuf {
        if let Some(rel) = path.strip_prefix("./") {
            self.dir.join(rel)
        } else if path == "~" {
            self.home.clone()
        } else if let Some(rel) = path.strip_prefix("~/") {
            self.home.join(rel)
        } else {
            PathBuf::from(path)
        }
    }

    fn file(&mut self, path: &Path) {
        // A file that sources itself would otherwise never end.
        if self.stack.iter().any(|p| p == path) {
            return;
        }
        let Some(text) = (self.read)(path) else { return };
        self.stack.push(path.to_path_buf());
        for raw in text.lines() {
            if raw.starts_with('#') || raw.is_empty() {
                continue;
            }
            let Some((key, value)) = strip_comment(raw).split_once('=') else { continue };
            let (key, value) = (key.trim(), value.trim());
            let value = expand(value, &self.vars);
            match key {
                "var" => {
                    if let Some((name, v)) = value.split_once(',') {
                        self.vars.insert(name.trim().to_owned(), v.trim().to_owned());
                    }
                }
                "key_mode" => self.key_mode = value,
                "xkb_rules_layout" => {
                    self.out.layouts = value.split(',').map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned).collect();
                }
                k if k.starts_with("source") => {
                    let next = self.resolve(&value);
                    self.file(&next);
                }
                k => {
                    if let Some(bind) = keybinds::parse_mango_bind(k, &value, &self.key_mode) {
                        self.out.binds.push(bind);
                    }
                }
            }
        }
        self.stack.pop();
    }
}

/// `entry` and everything it sources. `None` when `entry` itself cannot be
/// read; a missing sourced file is skipped, as mango skips an optional one.
pub fn read(entry: &Path, home: &Path, read: &dyn Fn(&Path) -> Option<String>) -> Option<Read> {
    read(entry)?;
    let dir = entry.parent().map(Path::to_path_buf).unwrap_or_default();
    let mut walk = Walk {
        read,
        home: home.to_path_buf(),
        dir,
        vars: HashMap::new(),
        key_mode: "default".into(),
        out: Read::default(),
        stack: Vec::new(),
    };
    walk.file(entry);
    Some(walk.out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn walks_sources_vars_and_modes() {
        let files: HashMap<PathBuf, &str> = HashMap::from([
            (
                PathBuf::from("/h/.config/mango/config.conf"),
                "# top\nvar=term,foot\nxkb_rules_layout=us, de\nbind=SUPER,Return,spawn,$term # a comment\nsource=./binds.conf\nsource_optional=~/missing.conf\nsource=/h/.config/mango/config.conf\n",
            ),
            (PathBuf::from("/h/.config/mango/binds.conf"), "key_mode=resize\nbind=NONE,Left,resizewin,-10,0\nkey_mode=default\nbindl=SUPER,L,spawn,${term}x\n"),
        ]);
        let reader = |p: &Path| files.get(p).map(|s| (*s).to_owned());
        let out = read(Path::new("/h/.config/mango/config.conf"), Path::new("/h"), &reader).unwrap();
        assert_eq!(out.layouts, ["us", "de"]);
        let first: Vec<(&str, String, &str)> =
            out.binds.iter().map(|b| (b.chord.as_str(), keybinds::describe_action(b), b.submap.as_str())).collect();
        assert_eq!(
            first,
            [
                ("SUPER+Return", "spawn foot".to_string(), ""),
                ("Left", "resizewin -10,0".to_string(), "resize"),
                ("SUPER+L", "spawn footx".to_string(), ""),
            ]
        );
        assert!(read(Path::new("/nope"), Path::new("/h"), &reader).is_none());
    }

    #[test]
    fn expansion_leaves_unknown_names() {
        let vars = HashMap::from([("a".to_string(), "1".to_string())]);
        assert_eq!(expand("$a-${a}-$b-$-${", &vars), "1-1-$b-$-${");
    }

    #[test]
    fn the_shipped_example_parses_every_bind() {
        // The package build's source is crates/ alone, so the example is
        // only there in a checkout.
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/examples/mango/formalshell.conf");
        let Ok(text) = std::fs::read_to_string(&path) else { return };
        let entry = Path::new("/h/.config/mango/formalshell.conf");
        let reader = |p: &Path| (p == entry).then(|| text.clone());
        let out = read(entry, Path::new("/h"), &reader).unwrap();
        let lines = text.lines().filter(|l| l.starts_with("bind")).count();
        assert!(lines > 50);
        assert_eq!(out.binds.len(), lines);
        assert!(out.binds.iter().any(|b| b.chord == "SUPER+space" && keybinds::describe_action(b) == "spawn formalshell-ipc call menu toggle"));
    }
}
