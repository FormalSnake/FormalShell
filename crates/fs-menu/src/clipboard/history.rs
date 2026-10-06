//! Pure clipboard-history reducer: capped, de-duplicated by content, newest
//! first. Every function takes state in and returns state out; there is no
//! clock and no mutation of the input. Image entries dedupe by `path`: the
//! capture side content-addresses the file by its sha256, so path equality
//! already is content equality. The mutating reducers return the image paths
//! any eviction just orphaned, and the caller deletes the files; nothing here
//! touches the filesystem.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

pub const MAX_ENTRIES: usize = 300;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum EntryKind {
    #[default]
    Text,
    Image,
}

impl Serialize for EntryKind {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            EntryKind::Text => "text",
            EntryKind::Image => "image",
        })
    }
}

/// Entries persisted before images existed carry no `kind`: anything that is
/// not "image" reads as text, a pure migration with no file rewrite.
impl<'de> Deserialize<'de> for EntryKind {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<EntryKind, D::Error> {
        let v = Option::<String>::deserialize(d)?;
        Ok(if v.as_deref() == Some("image") { EntryKind::Image } else { EntryKind::Text })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub kind: EntryKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub captured_at: Option<i64>,
}

impl Entry {
    pub fn text(id: &str, text: &str) -> Entry {
        Entry { id: id.to_string(), kind: EntryKind::Text, text: Some(text.to_string()), ..Entry::default() }
    }

    pub fn image(id: &str, path: &str) -> Entry {
        Entry { id: id.to_string(), kind: EntryKind::Image, path: Some(path.to_string()), ..Entry::default() }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct State {
    pub items: Vec<Entry>,
}

/// The new state plus the image paths the change orphaned.
#[derive(Clone, Debug, PartialEq)]
pub struct Reduced {
    pub state: State,
    pub removed_paths: Vec<String>,
}

pub fn initial_state() -> State {
    State::default()
}

fn no_removal(state: &State) -> Reduced {
    Reduced { state: state.clone(), removed_paths: Vec::new() }
}

/// Drops empty and whitespace-only captures (the shape a clipboard clear
/// event produces) and returns the text unchanged otherwise; real content is
/// never trimmed.
///
/// NUL bytes are stripped before the empty check. Quickshell's SplitParser
/// skips the byte directly after a delimiter match, so two adjacent NULs in
/// the watcher's stream leak one into the front of the next entry: an empty
/// capture followed by a real one recorded `\0/tmp/shot.png` alongside the
/// clean `/tmp/shot.png`. Stripping rather than rejecting collapses that pair
/// back into one row, and a NUL could never survive wl-copy's argv anyway.
pub fn sanitize(text: &str) -> Option<String> {
    let stripped: String = text.chars().filter(|&c| c != '\0').collect();
    if fs_js::trim(&stripped).is_empty() { None } else { Some(stripped) }
}

/// Reads an entry out of persisted JSON, migrating a legacy one (no `kind`)
/// to text. `None` when the value is not an object.
pub fn normalize_entry(value: &Value) -> Option<Entry> {
    if !value.is_object() {
        return None;
    }
    serde_json::from_value(value.clone()).ok()
}

fn image_paths_of(entries: &[Entry]) -> Vec<String> {
    entries
        .iter()
        .filter(|e| e.kind == EntryKind::Image)
        .map(|e| e.path.clone().unwrap_or_default())
        .collect()
}

fn cap_overflow(mut items: Vec<Entry>) -> (Vec<Entry>, Vec<String>) {
    if items.len() <= MAX_ENTRIES {
        return (items, Vec::new());
    }
    let overflow = items.split_off(MAX_ENTRIES);
    (items, image_paths_of(&overflow))
}

/// A capture to add. Text and image entries share a shape; `kind` picks the
/// reducer, and an entry that is not an image is text.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct NewEntry {
    pub id: String,
    pub kind: EntryKind,
    pub text: Option<String>,
    pub path: Option<String>,
    pub mime: Option<String>,
}

/// Re-copying content already in history moves the existing entry to the
/// front (refreshing `captured_at`) instead of inserting a duplicate; the new
/// entry keeps the OLD id, so anything holding a reference to it (a pending
/// copy or remove) still resolves.
fn add_text(state: &State, entry: &NewEntry, now: i64) -> Reduced {
    let Some(text) = entry.text.as_deref().and_then(sanitize) else { return no_removal(state) };

    let mut items = state.items.clone();
    let mut id = entry.id.clone();
    if let Some(idx) = items.iter().position(|i| i.kind != EntryKind::Image && i.text.as_deref() == Some(&text)) {
        id = items.remove(idx).id;
    }
    items.insert(
        0,
        Entry { id, kind: EntryKind::Text, text: Some(text), captured_at: Some(now), ..Entry::default() },
    );
    let (items, removed_paths) = cap_overflow(items);
    Reduced { state: State { items }, removed_paths }
}

fn add_image(state: &State, entry: &NewEntry, now: i64) -> Reduced {
    let Some(path) = entry.path.as_deref().filter(|p| !p.is_empty()) else { return no_removal(state) };

    let mut items = state.items.clone();
    let mut id = entry.id.clone();
    if let Some(idx) = items.iter().position(|i| i.kind == EntryKind::Image && i.path.as_deref() == Some(path)) {
        id = items.remove(idx).id;
    }
    let mime = entry.mime.clone().filter(|m| !m.is_empty()).unwrap_or_else(|| "image/png".to_string());
    items.insert(
        0,
        Entry {
            id,
            kind: EntryKind::Image,
            path: Some(path.to_string()),
            mime: Some(mime),
            captured_at: Some(now),
            ..Entry::default()
        },
    );
    let (items, removed_paths) = cap_overflow(items);
    Reduced { state: State { items }, removed_paths }
}

pub fn add(state: &State, entry: &NewEntry, now: i64) -> Reduced {
    if entry.kind == EntryKind::Image { add_image(state, entry, now) } else { add_text(state, entry, now) }
}

pub fn remove(state: &State, id: &str) -> Reduced {
    let Some(idx) = state.items.iter().position(|i| i.id == id) else { return no_removal(state) };
    let mut items = state.items.clone();
    let removed = items.remove(idx);
    let removed_paths = if removed.kind == EntryKind::Image { vec![removed.path.unwrap_or_default()] } else { Vec::new() };
    Reduced { state: State { items }, removed_paths }
}

/// A copied file reaches the text watcher too, as its own path or uri. Once
/// the same copy has landed as an image that row is its echo. Only the newest
/// row, and only inside `window_ms` of `now`: the echo is always the capture
/// that just happened, never a row further down.
pub fn drop_echo(state: &State, texts: &[&str], now: i64, window_ms: i64) -> State {
    let Some(top) = state.items.first() else { return state.clone() };
    if top.kind == EntryKind::Image || top.captured_at.is_some_and(|at| now - at > window_ms) {
        return state.clone();
    }
    let top_text = fs_js::trim(top.text.as_deref().unwrap_or(""));
    if !texts.contains(&top_text) {
        return state.clone();
    }
    State { items: state.items[1..].to_vec() }
}

pub fn clear(state: &State) -> Reduced {
    if state.items.is_empty() {
        return no_removal(state);
    }
    Reduced { state: State::default(), removed_paths: image_paths_of(&state.items) }
}
