//! `~/.config/formalshell/settings.json`, read and never written. Every
//! consumer asks for a dotted path and brings its own default, so the state
//! is the parsed document and a diff names the keys that changed.

use std::path::PathBuf;

use serde_json::{Map, Value};

use super::watch::Watch;
use crate::runtime::Ctx;
use crate::store;

pub struct State {
    settings: Value,
    /// True once settings.json has been resolved one way or another (parsed,
    /// or confirmed absent), and never false again.
    pub loaded: bool,
}

impl Default for State {
    fn default() -> Self {
        Self { settings: Value::Object(Map::new()), loaded: false }
    }
}

/// One leaf that changed: its path, and its new value or `None` when it is
/// gone. Objects are walked into; anything else is a leaf, as is an object
/// that replaced a non-object (or the reverse).
#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    pub path: Vec<String>,
    pub value: Option<Value>,
}

#[derive(Debug, Default, PartialEq)]
pub struct Diff {
    pub loaded: bool,
    pub changes: Vec<Change>,
}

impl State {
    /// True when the slice differs afterwards.
    pub fn apply(&mut self, diff: Diff) -> bool {
        let mut changed = diff.loaded && !self.loaded;
        self.loaded |= diff.loaded;
        for change in diff.changes {
            changed = true;
            set(&mut self.settings, &change.path, change.value);
        }
        changed
    }

    /// Dotted-path lookup. Walks objects and arrays (an index is a path
    /// segment); `None` where the path leaves the document, `Some(Null)`
    /// where it ends on a null.
    pub fn get(&self, path: &str) -> Option<&Value> {
        let mut node = &self.settings;
        for part in path.split('.') {
            node = match node {
                Value::Object(map) => map.get(part)?,
                Value::Array(items) => items.get(part.parse::<usize>().ok()?)?,
                _ => return None,
            };
        }
        Some(node)
    }

    pub fn str(&self, path: &str) -> Option<&str> {
        self.get(path)?.as_str()
    }

    pub fn bool(&self, path: &str) -> Option<bool> {
        self.get(path)?.as_bool()
    }

    pub fn f64(&self, path: &str) -> Option<f64> {
        self.get(path)?.as_f64()
    }

    /// The profile picture the lock screen and the polkit card show.
    pub fn avatar_path(&self, home: &str) -> String {
        match self.str("avatar.path") {
            Some(p) if !p.is_empty() => p.to_string(),
            _ => format!("{home}/.face"),
        }
    }
}

fn set(root: &mut Value, path: &[String], value: Option<Value>) {
    let Some((last, parents)) = path.split_last() else {
        *root = value.unwrap_or(Value::Null);
        return;
    };
    let mut node = root;
    for key in parents {
        if !node.is_object() {
            *node = Value::Object(Map::new());
        }
        node = node.as_object_mut().unwrap().entry(key.clone()).or_insert_with(|| Value::Object(Map::new()));
    }
    if !node.is_object() {
        *node = Value::Object(Map::new());
    }
    let map = node.as_object_mut().unwrap();
    match value {
        Some(v) => {
            map.insert(last.clone(), v);
        }
        None => {
            map.remove(last);
        }
    }
}

fn walk(path: &mut Vec<String>, old: Option<&Value>, new: Option<&Value>, out: &mut Vec<Change>) {
    if old == new {
        return;
    }
    if let (Some(Value::Object(a)), Some(Value::Object(b))) = (old, new) {
        let mut keys: Vec<&String> = a.keys().chain(b.keys()).collect();
        keys.sort();
        keys.dedup();
        for key in keys {
            path.push(key.clone());
            walk(path, a.get(key), b.get(key), out);
            path.pop();
        }
        return;
    }
    out.push(Change { path: path.clone(), value: new.cloned() });
}

/// What publishing a read of settings.json does: tracks the bytes last
/// published and the document they parsed to, and turns a new read into the
/// keys that moved.
pub struct Resolver {
    published: Option<String>,
    settings: Value,
    loaded: bool,
}

impl Default for Resolver {
    fn default() -> Self {
        Self { published: None, settings: Value::Object(Map::new()), loaded: false }
    }
}

impl Resolver {
    /// `text` is the file's contents, or "" when it is missing or unreadable.
    /// A read that finds the same bytes does nothing, and a file that does
    /// not parse keeps the last good document and returns the warning to log.
    pub fn publish(&mut self, text: &str) -> (Diff, Option<String>) {
        let first = !self.loaded;
        self.loaded = true;
        let mut diff = Diff { loaded: first, ..Diff::default() };
        if !first && self.published.as_deref() == Some(text) {
            return (diff, None);
        }
        self.published = Some(text.to_string());
        let next = if text.is_empty() {
            Value::Object(Map::new())
        } else {
            match serde_json::from_str::<Value>(text) {
                Ok(v) => v,
                Err(e) => return (diff, Some(format!("Config: failed to parse settings.json: {e}"))),
            }
        };
        walk(&mut Vec::new(), Some(&self.settings), Some(&next), &mut diff.changes);
        self.settings = next;
        (diff, None)
    }
}

pub fn settings_path() -> PathBuf {
    let dir = match std::env::var("XDG_CONFIG_HOME") {
        Ok(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config"),
    };
    dir.join("formalshell").join("settings.json")
}

fn describe(diff: &Diff) -> String {
    let paths: Vec<String> = diff.changes.iter().map(|c| c.path.join(".")).collect();
    format!("config: settings.json read, {} key(s) changed [{}]", paths.len(), paths.join(", "))
}

pub async fn run(ctx: Ctx) {
    let path = settings_path();
    let mut resolver = Resolver::default();
    let mut watch = match Watch::new(path.clone()) {
        Ok(watch) => Some(watch),
        Err(e) => {
            eprintln!("config: no watch on {}: {e}", path.display());
            None
        }
    };
    loop {
        let read = path.clone();
        let text = ctx.pool().run(move || std::fs::read_to_string(read).unwrap_or_default()).await;
        let (diff, warning) = resolver.publish(&text.unwrap_or_default());
        if let Some(warning) = warning {
            eprintln!("{warning}");
        }
        if diff.loaded || !diff.changes.is_empty() {
            if !diff.changes.is_empty() {
                eprintln!("{}", describe(&diff));
            }
            ctx.publish(store::Diff::Config(diff));
        }
        match watch.as_mut() {
            Some(watch) => watch.changed().await,
            None => std::future::pending().await,
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn state(text: &str) -> State {
        let mut state = State::default();
        let (diff, _) = Resolver::default().publish(text);
        state.apply(diff);
        state
    }

    #[test]
    fn get_walks_dotted_paths_and_falls_back() {
        let s = state(r#"{"menu":{"customPowerButtons":[{"label":"x"}]},"a":{"b":null},"n":5}"#);
        assert_eq!(s.get("menu.customPowerButtons.0.label"), Some(&json!("x")));
        assert_eq!(s.get("menu.missing"), None);
        assert_eq!(s.get("n.deeper"), None, "a scalar has no children");
        assert_eq!(s.get("a.b"), Some(&Value::Null), "a null is a value, not a miss");
        assert_eq!(s.get("menu.customPowerButtons.9"), None);
        assert_eq!(s.f64("n"), Some(5.0));
    }

    #[test]
    fn avatar_defaults_to_home_face() {
        assert_eq!(state("{}").avatar_path("/home/k"), "/home/k/.face");
        assert_eq!(state(r#"{"avatar":{"path":""}}"#).avatar_path("/home/k"), "/home/k/.face");
        assert_eq!(state(r#"{"avatar":{"path":"/p.png"}}"#).avatar_path("/home/k"), "/p.png");
    }

    #[test]
    fn missing_file_resolves_to_empty_and_loads_once() {
        let mut r = Resolver::default();
        let (first, warning) = r.publish("");
        assert!(first.loaded && first.changes.is_empty() && warning.is_none());
        let (again, _) = r.publish("");
        assert_eq!(again, Diff::default(), "loaded never flips twice");
    }

    #[test]
    fn identical_bytes_publish_nothing() {
        let mut r = Resolver::default();
        let (first, _) = r.publish(r#"{"bar":{"position":"left"}}"#);
        assert_eq!(first.changes.len(), 1);
        let (same, _) = r.publish(r#"{"bar":{"position":"left"}}"#);
        assert_eq!(same, Diff::default());
    }

    #[test]
    fn reformatted_file_with_the_same_structure_publishes_nothing() {
        let mut r = Resolver::default();
        r.publish(r#"{"a":1,"b":2}"#);
        let (diff, _) = r.publish("{\n  \"b\": 2,\n  \"a\": 1\n}");
        assert!(diff.changes.is_empty());
    }

    #[test]
    fn diff_names_only_the_keys_that_moved() {
        let mut r = Resolver::default();
        r.publish(r#"{"bar":{"position":"right","layout":{"left":["a"]}},"gone":1,"same":true}"#);
        let (diff, _) = r.publish(r#"{"bar":{"position":"left","layout":{"left":["a"]}},"added":{"x":1},"same":true}"#);
        let paths: Vec<_> = diff.changes.iter().map(|c| (c.path.join("."), c.value.clone())).collect();
        assert_eq!(
            paths,
            [
                ("added".to_string(), Some(json!({"x": 1}))),
                ("bar.position".to_string(), Some(json!("left"))),
                ("gone".to_string(), None),
            ]
        );
    }

    #[test]
    fn applying_diffs_reproduces_the_document() {
        let mut r = Resolver::default();
        let mut s = State::default();
        for text in [
            r#"{"a":{"b":1,"c":[1,2]},"d":"x"}"#,
            r#"{"a":{"b":2,"c":[1]},"e":{}}"#,
            r#"{"a":5}"#,
            r#"{"a":{"z":1}}"#,
            "",
        ] {
            let (diff, _) = r.publish(text);
            s.apply(diff);
            let want: Value = if text.is_empty() { json!({}) } else { serde_json::from_str(text).unwrap() };
            assert_eq!(s.settings, want, "after {text:?}");
        }
    }

    #[test]
    fn parse_failure_keeps_the_last_good_value_and_warns_once() {
        let mut r = Resolver::default();
        let (good, _) = r.publish(r#"{"a":1}"#);
        assert_eq!(good.changes.len(), 1);
        let (bad, warning) = r.publish(r#"{"a":"#);
        assert!(bad.changes.is_empty());
        assert!(warning.unwrap().starts_with("Config: failed to parse settings.json: "));
        let (again, warning) = r.publish(r#"{"a":"#);
        assert!(again.changes.is_empty() && warning.is_none(), "the same bad bytes are not re-reported");
        let (fixed, _) = r.publish(r#"{"a":2}"#);
        assert_eq!(fixed.changes, [Change { path: vec!["a".into()], value: Some(json!(2)) }]);
    }

    #[test]
    fn a_first_read_that_fails_to_parse_still_loads() {
        let (diff, warning) = Resolver::default().publish("nope");
        assert!(diff.loaded && warning.is_some());
    }

    #[test]
    fn apply_reports_whether_the_slice_moved() {
        let mut s = State::default();
        assert!(s.apply(Diff { loaded: true, changes: vec![] }));
        assert!(!s.apply(Diff { loaded: true, changes: vec![] }));
        let change = Change { path: vec!["a".into()], value: Some(json!(1)) };
        assert!(s.apply(Diff { loaded: false, changes: vec![change] }));
    }
}
