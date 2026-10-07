//! The launcher's footer (actions.js) and the row accessory (hints.js): what
//! Enter does to the row under the cursor, the keys that always apply beside
//! it, and the muted value a row carries on its right.
//!
//! Verbs come from a node's `kind`, never from its id; a provider that knows
//! better says so in the row's own `verb`. A `dim` row gets no primary action
//! rather than a verb that would do nothing. Keys are names, one per cap.

use crate::model::Mode;
use crate::node::{Kind, Node};

/// One legend entry: the keys of a chord (or keys offered side by side) and
/// the outcome they name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyHint {
    pub keys: Vec<&'static str>,
    pub label: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionBar {
    pub primary: Option<KeyHint>,
    pub hints: Vec<KeyHint>,
}

/// Which variant the wallpaper route's Tab would show.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Variant {
    Dark,
    Light,
}

/// What the menu hands the footer.
#[derive(Clone, Debug)]
pub struct ActionCtx<'a> {
    pub mode: Mode,
    pub node: Option<&'a Node>,
    pub at_root: bool,
    pub picker_select: bool,
    /// The variant Tab would switch to, `None` wherever Tab does nothing.
    pub variant_switch: Option<Variant>,
    pub confirming: bool,
    pub discrete_gpu: bool,
    pub clipssh_image: bool,
    /// A row's own Shift+Enter verb, "" for none.
    pub alternate_label: &'a str,
}

impl Default for ActionCtx<'_> {
    fn default() -> Self {
        Self {
            mode: Mode::Menu,
            node: None,
            at_root: false,
            picker_select: false,
            variant_switch: None,
            confirming: false,
            discrete_gpu: false,
            clipssh_image: false,
            alternate_label: "",
        }
    }
}

const KEY_ENTER: &[&str] = &["Enter"];
const KEY_ESC: &[&str] = &["Esc"];
const KEY_TAB: &[&str] = &["Tab"];
const KEY_SHIFT_ENTER: &[&str] = &["Shift", "Enter"];

fn hint(keys: &[&'static str], label: impl Into<String>) -> KeyHint {
    KeyHint { keys: keys.to_vec(), label: label.into() }
}

pub fn primary_action(c: &ActionCtx) -> Option<KeyHint> {
    if c.mode == Mode::Input {
        return Some(hint(KEY_ENTER, "Submit"));
    }
    let node = c.node?;
    if node.dim == Some(true) {
        return None;
    }
    if c.confirming {
        return Some(hint(KEY_ENTER, format!("Confirm {}", node.label)));
    }
    if let Some(verb) = node.verb.as_deref().filter(|v| !v.is_empty()) {
        return Some(hint(KEY_ENTER, verb));
    }
    let label = match node.kind {
        Kind::Other(ref k) if k == "option" => "Select",
        Kind::Image if c.picker_select => "Choose",
        Kind::Image => "Set wallpaper",
        Kind::App | Kind::Submenu | Kind::Provider | Kind::Link => "Open",
        Kind::Action => "Run",
        _ => return None,
    };
    Some(hint(KEY_ENTER, label))
}

/// The keys beside Enter. Escape reads Back wherever there is a level to pop
/// and Close at the root, since those are two different outcomes.
pub fn hints(c: &ActionCtx) -> Vec<KeyHint> {
    if c.mode == Mode::Input {
        return vec![hint(KEY_ESC, "Cancel")];
    }
    let mut out = Vec::new();
    match c.variant_switch {
        Some(Variant::Light) => out.push(hint(KEY_TAB, "Show light")),
        Some(Variant::Dark) => out.push(hint(KEY_TAB, "Show dark")),
        None => {}
    }
    if c.discrete_gpu && c.node.is_some_and(|n| n.kind == Kind::App) && !c.confirming {
        out.push(hint(KEY_SHIFT_ENTER, "Open on GPU"));
    }
    if c.clipssh_image && !c.confirming {
        out.push(hint(KEY_SHIFT_ENTER, "Send over SSH"));
    }
    if !c.alternate_label.is_empty() && !c.confirming {
        out.push(hint(KEY_SHIFT_ENTER, c.alternate_label));
    }
    if c.mode == Mode::Select {
        out.push(hint(KEY_ESC, "Cancel"));
    } else {
        out.push(hint(KEY_ESC, if c.at_root { "Close" } else { "Back" }));
    }
    out
}

pub fn action_bar(c: &ActionCtx) -> ActionBar {
    ActionBar { primary: primary_action(c), hints: hints(c) }
}

/// The chords that summon a route directly, as a reader would type them.
pub const ROUTE_CHORDS: &[(&str, &str)] = &[
    ("apps", "Super+Alt+Space"),
    ("calc", "Super+Ctrl+Q"),
    ("capture", "Super+Ctrl+C"),
    ("clipboard", "Super+Ctrl+V"),
    ("emoji", "Super+Ctrl+E"),
    ("keybinds", "Super+K"),
    ("reminder", "Super+Ctrl+R"),
    ("share", "Super+Ctrl+S"),
    ("system", "Super+Escape"),
    ("theme", "Super+Shift+Ctrl+Space"),
    ("toggles", "Super+Ctrl+O"),
    ("wallpaper", "Super+Ctrl+Space"),
];

/// What a route answers to when typed as a prefix from any level.
pub const ROUTE_PREFIXES: &[(&str, &str)] = &[("emoji", ":e"), ("nix", ":nix"), ("keybinds", ":k")];

fn lookup(table: &[(&str, &'static str)], id: &str) -> &'static str {
    table.iter().find(|(k, _)| *k == id).map_or("", |(_, v)| v)
}

pub fn chord_for(id: &str) -> &'static str {
    lookup(ROUTE_CHORDS, id)
}

/// A count only for a provider node, whose children are a listing; zero reads
/// as no hint at all.
pub fn count_for(node: Option<&Node>) -> String {
    match node {
        Some(n) if n.kind == Kind::Provider && !n.child_ids.is_empty() => n.child_ids.len().to_string(),
        _ => String::new(),
    }
}

/// The chord wins over the count.
pub fn hint_for(node: Option<&Node>) -> String {
    let Some(n) = node else { return String::new() };
    let chord = chord_for(&n.id);
    if chord.is_empty() { count_for(node) } else { chord.to_string() }
}

/// The row's right-aligned accessory: its own value, else what the row is.
pub fn accessory_for(node: Option<&Node>) -> String {
    let Some(n) = node else { return String::new() };
    if let Some(meta) = n.meta.as_deref().filter(|m| !m.is_empty()) {
        return meta.to_string();
    }
    match n.kind {
        Kind::App => "Application".into(),
        Kind::Action => if n.verb.as_deref().is_some_and(|v| !v.is_empty()) { "" } else { "Command" }.into(),
        Kind::Submenu | Kind::Provider | Kind::Link => {
            let prefix = lookup(ROUTE_PREFIXES, &n.id);
            if prefix.is_empty() { hint_for(node) } else { prefix.into() }
        }
        _ => String::new(),
    }
}

/// The accessory as a chord's keys, one per cap, when that is what it is.
pub fn chord_keys_for(node: Option<&Node>) -> Vec<&'static str> {
    let Some(n) = node else { return Vec::new() };
    let chord = chord_for(&n.id);
    if chord.is_empty() || accessory_for(node) != chord {
        return Vec::new();
    }
    chord.split('+').collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn labels(h: &[KeyHint]) -> Vec<&str> {
        h.iter().map(|k| k.label.as_str()).collect()
    }

    #[test]
    fn primary_by_kind() {
        let app = Node::new("apps.x", "X", Kind::App);
        let act = Node::new("a", "Lock", Kind::Action);
        let img = Node::new("i", "i", Kind::Image);
        let opt = Node::new("select.0", "o", Kind::Other("option".into()));
        let ctx = |n| ActionCtx { node: Some(n), ..Default::default() };
        assert_eq!(primary_action(&ctx(&app)).unwrap().label, "Open");
        assert_eq!(primary_action(&ctx(&act)).unwrap().label, "Run");
        assert_eq!(primary_action(&ctx(&img)).unwrap().label, "Set wallpaper");
        assert_eq!(primary_action(&ActionCtx { picker_select: true, ..ctx(&img) }).unwrap().label, "Choose");
        assert_eq!(primary_action(&ctx(&opt)).unwrap().label, "Select");
        assert_eq!(primary_action(&ActionCtx { confirming: true, ..ctx(&act) }).unwrap().label, "Confirm Lock");
        let verb = Node { verb: Some("Paste".into()), ..act.clone() };
        assert_eq!(primary_action(&ctx(&verb)).unwrap().label, "Paste");
        assert_eq!(primary_action(&ctx(&Node::note("n", "none"))), None);
        assert_eq!(primary_action(&ActionCtx::default()), None);
        let input = ActionCtx { mode: Mode::Input, ..Default::default() };
        assert_eq!(primary_action(&input).unwrap().label, "Submit");
        assert_eq!(labels(&hints(&input)), ["Cancel"]);
    }

    #[test]
    fn hints_by_context() {
        let app = Node::new("apps.x", "X", Kind::App);
        assert_eq!(labels(&hints(&ActionCtx { at_root: true, ..Default::default() })), ["Close"]);
        assert_eq!(labels(&hints(&ActionCtx::default())), ["Back"]);
        assert_eq!(labels(&hints(&ActionCtx { mode: Mode::Select, ..Default::default() })), ["Cancel"]);
        let c = ActionCtx {
            node: Some(&app),
            discrete_gpu: true,
            variant_switch: Some(Variant::Light),
            alternate_label: "Alt",
            ..Default::default()
        };
        assert_eq!(labels(&hints(&c)), ["Show light", "Open on GPU", "Alt", "Back"]);
        assert_eq!(hints(&c)[1].keys, ["Shift", "Enter"]);
        assert_eq!(labels(&hints(&ActionCtx { confirming: true, ..c })), ["Show light", "Back"]);
    }

    #[test]
    fn accessories() {
        let app = Node::new("apps.x", "X", Kind::App);
        assert_eq!(accessory_for(Some(&app)), "Application");
        assert_eq!(accessory_for(Some(&Node::new("a", "a", Kind::Action))), "Command");
        let emoji = Node::new("emoji", "Emoji", Kind::Provider);
        assert_eq!(accessory_for(Some(&emoji)), ":e");
        let clip = Node::new("clipboard", "Clipboard", Kind::Provider);
        assert_eq!(accessory_for(Some(&clip)), "Super+Ctrl+V");
        assert_eq!(chord_keys_for(Some(&clip)), ["Super", "Ctrl", "V"]);
        assert!(chord_keys_for(Some(&emoji)).is_empty());
        let tray = Node { child_ids: vec!["a".into(), "b".into()], ..Node::new("tray", "Tray", Kind::Provider) };
        assert_eq!(accessory_for(Some(&tray)), "2");
        let meta = Node { meta: Some("42%".into()), ..app };
        assert_eq!(accessory_for(Some(&meta)), "42%");
        assert_eq!(accessory_for(None), "");
    }
}
