//! Compositor keybinds to menu rows. The mapping and the ranking are pure; the
//! hyprctl process stays in the menu surface.
//!
//! The input is `hyprctl binds`, with hyprland's own dofiles and submaps
//! already expanded, so there is no include chain to walk here. Nothing
//! panics: unreadable output yields an empty list, which the surface renders as
//! an honest unavailable row rather than a warning.

use fs_js as js;
use regex::Regex;
use std::collections::HashMap;
use std::sync::LazyLock;

pub const KEYBINDS_CHORD_PAD_MAX: usize = 24;
pub const KEYBINDS_MAX_RESULTS: usize = 200;

/// Chords are padded into a column with U+00A0, not ASCII space: a text item's
/// implicit width drops trailing ASCII whitespace, so a space-padded label
/// would measure as the bare chord and the column would collapse.
const PAD_CHAR: char = '\u{a0}';

/// wlroots' modifier bits (WLR_MODIFIER_*, the table hyprland's stringToModMask
/// writes), listed in the order a chord is conventionally written rather than
/// in bit order, so 65 reads "SUPER+SHIFT" and not "SHIFT+SUPER".
const HYPR_MODS: [(u32, &str); 8] = [
    (64, "SUPER"),
    (4, "CTRL"),
    (8, "ALT"),
    (1, "SHIFT"),
    (2, "CAPS"),
    (16, "MOD2"),
    (32, "MOD3"),
    (128, "MOD5"),
];

#[derive(Debug, Clone, PartialEq, Default)]
pub struct BindProps {
    pub submap: String,
    pub catchall: String,
}

/// `chord: "SUPER+SHIFT+slash"`, `mods: ["SUPER", "SHIFT"]`, `key: "slash"`,
/// `action: "exec"`, `args: ["formalshell-ipc call menu toggle"]`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Bind {
    pub chord: String,
    pub mods: Vec<String>,
    pub key: String,
    pub action: String,
    pub args: Vec<String>,
    pub title: String,
    pub props: BindProps,
}

fn hypr_mods(modmask: &str) -> Vec<String> {
    let n = js::parse_number(modmask);
    let mask = if n.is_nan() { 0 } else { n as i64 as u32 };
    HYPR_MODS.iter().filter(|(bit, _)| mask & bit != 0).map(|(_, name)| name.to_string()).collect()
}

fn bind_from_fields(fields: &HashMap<String, String>) -> Bind {
    let get = |k: &str| fields.get(k).map_or("", String::as_str);
    let mods = hypr_mods(get("modmask"));
    // An empty `key` means the bind was written against a raw keycode
    // (hyprland's own `code:XX` spelling), which is what it reports back.
    let mut key = get("key").to_string();
    if key.is_empty() {
        key = format!("code:{}", get("keycode"));
    }
    let arg = get("arg");
    // A Lua bind reports the dispatcher `__lua` and, as its arg, an internal
    // reference number: neither says anything, so the bind's own description is
    // the only action text it has.
    let is_lua = get("dispatcher") == "__lua";
    let mut chord_parts = mods.clone();
    chord_parts.push(key.clone());
    Bind {
        chord: chord_parts.join("+"),
        mods,
        key,
        action: if is_lua { String::new() } else { get("dispatcher").to_string() },
        args: if arg.is_empty() || is_lua { Vec::new() } else { vec![arg.to_string()] },
        title: get("description").to_string(),
        props: BindProps { submap: get("submap").to_string(), catchall: (get("catchall") == "true").to_string() },
    }
}

static BIND_HEADER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^bind[a-z]*$").unwrap());
static FIELD_LINE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[ \t]+([A-Za-z_][A-Za-z0-9_]*): ?(.*)$").unwrap());

/// `hyprctl binds`, the plain-text table. Deliberately NOT `-j`: Hyprland
/// 0.56.0's JSON encoder puts every value from `modmask` on under the PREVIOUS
/// key's name and emits `allow_input_capture` with no value at all, so the
/// reply is not JSON and parsing it cost the route every row it had. The text
/// table carries the same binds correctly.
///
/// One block per bind, headed by a bare `bind` line with one letter per flag the
/// bind carries (`bindd` a description, `bindel` locked and repeating), then one
/// tab-indented `name: value` field per line, blocks separated by a blank line.
/// A value may be empty and may itself hold a colon, so only the first one
/// splits.
pub fn parse_hyprland_binds(text: &str) -> Vec<Bind> {
    let mut out = Vec::new();
    let mut fields: Option<HashMap<String, String>> = None;

    for raw in text.split('\n') {
        let line = js::trim_end(raw);
        if BIND_HEADER.is_match(line) {
            if let Some(f) = &fields {
                out.push(bind_from_fields(f));
            }
            fields = Some(HashMap::new());
            continue;
        }
        let Some(f) = fields.as_mut() else { continue };
        if let Some(m) = FIELD_LINE.captures(line) {
            f.insert(m[1].to_string(), m[2].to_string());
        } else if line.is_empty() {
            out.push(bind_from_fields(f));
            fields = None;
        }
    }
    if let Some(f) = &fields {
        out.push(bind_from_fields(f));
    }
    out
}

pub fn describe_action(bind: &Bind) -> String {
    let mut parts = vec![bind.action.clone()];
    parts.extend(bind.args.iter().cloned());
    let text = js::trim(&parts.join(" ")).to_string();
    if text.is_empty() { bind.title.clone() } else { text }
}

/// ":k" root trigger, the same shape the ":e"/":nix" triggers use: the query
/// after it, "" for the bare trigger, `None` when `text` is not the trigger at
/// all.
pub fn trigger_query(text: &str) -> Option<String> {
    if text == ":k" {
        return Some(String::new());
    }
    text.strip_prefix(":k ").map(String::from)
}

/// Chords and action names are "+"/"-"/"_"-joined, so a bare contains test
/// would rank "space" against togglespecialworkspace no higher than an
/// accidental substring hit.
const WORD_BREAK: &str = " +-_./";

fn word_start(hay: &str, q: &str) -> bool {
    let mut search_from = 0;
    while let Some(rel) = hay[search_from..].find(q) {
        let at = search_from + rel;
        if at == 0 {
            return true;
        }
        if hay[..at].chars().next_back().is_some_and(|c| WORD_BREAK.contains(c)) {
            return true;
        }
        // JS resumes one code unit past the hit, so overlapping matches count.
        search_from = at + hay[at..].chars().next().map_or(1, char::len_utf8);
    }
    false
}

/// Route-local search over chord, action and arguments: exact chord >
/// chord/action prefix > word start > contains, ties broken by config
/// declaration order. Deliberately never reaches the global search, which walks
/// the whole tree: a hundred-odd keybind rows there would drown every root
/// search, the same reason the emoji route is special-cased.
pub fn search(binds: &[Bind], query: &str) -> Vec<Bind> {
    let q = js::trim(query).to_lowercase();
    if q.is_empty() {
        return binds.iter().take(KEYBINDS_MAX_RESULTS).cloned().collect();
    }
    let mut results: Vec<(u8, usize)> = Vec::new();
    for (i, bind) in binds.iter().enumerate() {
        let chord = bind.chord.to_lowercase();
        let action = describe_action(bind).to_lowercase();
        let hay = format!("{chord} {action} {}", bind.title.to_lowercase());
        let tier = if chord == q {
            4
        } else if chord.starts_with(&q) || action.starts_with(&q) {
            3
        } else if word_start(&hay, &q) {
            2
        } else if hay.contains(&q) {
            1
        } else {
            continue;
        };
        results.push((tier, i));
    }
    results.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    results.into_iter().take(KEYBINDS_MAX_RESULTS).map(|(_, i)| binds[i].clone()).collect()
}

/// A launcher row. Content rows carry `dim: None`; the honest-unavailable rows
/// set it.
#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub id: String,
    pub parent_id: Option<String>,
    pub label: String,
    pub icon: String,
    pub title: String,
    pub desc: String,
    pub aliases: Vec<String>,
    pub kind: &'static str,
    pub dim: Option<bool>,
    pub child_ids: Vec<String>,
}

fn utf16_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// Rows are "note" kind, which the menu's activation has no branch for, so they
/// are inert by construction. That is the point: a bind acts on whatever window
/// has focus, and at Enter that is the menu, so running one from here would fire
/// it at whichever window the compositor hands focus back to instead of the one
/// the user was looking at.
///
/// No `dim` on a content row: the row keys the label's ink off it, and
/// `dim: true` belongs to the honest-unavailable rows below, not to a real
/// keybind. The chord rides `label` at content ink, the action rides `desc`
/// dimmed behind it.
///
/// The id carries the row index because duplicate chords are legal (two
/// submaps, a config declaring one twice) and the menu keys its node map by id.
pub fn rows(binds: &[Bind], query: &str) -> Vec<Row> {
    let matched = search(binds, query);
    let width = matched.iter().map(|b| utf16_len(&b.chord)).max().unwrap_or(0).min(KEYBINDS_CHORD_PAD_MAX);
    matched
        .iter()
        .enumerate()
        .map(|(i, bind)| {
            let len = utf16_len(&bind.chord);
            let pad: String = std::iter::repeat_n(PAD_CHAR, width.saturating_sub(len)).collect();
            Row {
                id: format!("keybinds.{i}.{}", bind.chord),
                parent_id: None,
                label: format!("{}{pad}", bind.chord),
                icon: String::new(),
                title: String::new(),
                desc: describe_action(bind),
                aliases: Vec::new(),
                kind: "note",
                dim: None,
                child_ids: Vec::new(),
            }
        })
        .collect()
}

/// The end states that are not a bind list. Each says what would fix it.
fn note_row(id: &str, label: &str, desc: &str) -> Row {
    Row {
        id: id.into(),
        parent_id: None,
        label: label.into(),
        icon: String::new(),
        title: String::new(),
        desc: desc.into(),
        aliases: Vec::new(),
        kind: "note",
        dim: Some(true),
        child_ids: Vec::new(),
    }
}

pub fn no_binds_row() -> Row {
    note_row("keybinds.nobinds", "No binds", "no binds in the hyprland config")
}

pub fn failed_row() -> Row {
    note_row("keybinds.failed", "Binds unavailable", "hyprctl binds failed")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Captured verbatim from Hyprland 0.56.0 inside the nested rig: the
    /// empty-valued fields, the tabs and the `bindd` header for the one bind
    /// carrying a description are all hyprland's own spelling.
    fn binds_text() -> String {
        [
            "bind", "\tmodmask: 65", "\tsubmap: ", "\tkey: slash", "\tkeycode: 0", "\tcatchall: false",
            "\tdescription: ", "\tdispatcher: exec", "\targ: hyprctl version", "",
            "bindd", "\tmodmask: 64", "\tsubmap: ", "\tkey: T", "\tkeycode: 0", "\tcatchall: false",
            "\tdescription: Open a Terminal", "\tdispatcher: exec", "\targ: ghostty", "",
            "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: Q", "\tkeycode: 0", "\tcatchall: false",
            "\tdescription: ", "\tdispatcher: killactive", "\targ: ", "",
            "bind", "\tmodmask: 68", "\tsubmap: ", "\tkey: 1", "\tkeycode: 0", "\tcatchall: false",
            "\tdescription: ", "\tdispatcher: movetoworkspace", "\targ: 1", "",
            "bind", "\tmodmask: 64", "\tsubmap: ", "\tkey: N", "\tkeycode: 0", "\tcatchall: false",
            "\tdescription: ", "\tdispatcher: exec", "\targ: notify-send {braces} // not-a-comment", "",
        ]
        .join("\n")
    }

    fn binds() -> Vec<Bind> {
        parse_hyprland_binds(&binds_text())
    }

    fn chords(list: &[Bind]) -> String {
        list.iter().map(|b| b.chord.as_str()).collect::<Vec<_>>().join(" ")
    }

    #[test]
    fn reads_every_block_in_declaration_order() {
        let b = binds();
        assert_eq!(b.len(), 5);
        assert_eq!(chords(&b), "SUPER+SHIFT+slash SUPER+T SUPER+Q SUPER+CTRL+1 SUPER+N");
    }

    #[test]
    fn modmask_expands_in_written_order() {
        let b = binds();
        assert_eq!(b[0].mods.join("+"), "SUPER+SHIFT");
        assert_eq!(b[0].key, "slash");
        assert_eq!(b[3].mods.join("+"), "SUPER+CTRL");
    }

    #[test]
    fn dispatcher_and_argument_split() {
        let b = binds();
        assert_eq!(b[0].action, "exec");
        assert_eq!(b[0].args.join(" "), "hyprctl version");
        assert_eq!(b[2].action, "killactive");
        assert_eq!(b[2].args.len(), 0);
        assert_eq!(b[3].args.join(" "), "1");
    }

    #[test]
    fn argument_holding_braces_and_slashes_survives() {
        assert_eq!(binds()[4].args[0], "notify-send {braces} // not-a-comment");
    }

    #[test]
    fn bindd_carries_its_description_as_the_title() {
        let b = binds();
        assert_eq!(b[1].title, "Open a Terminal");
        assert_eq!(b[0].title, "");
    }

    #[test]
    fn lua_bind_reads_its_description_as_the_action() {
        let text = [
            "bindeld", "\tmodmask: 0", "\tsubmap: ", "\tkey: XF86AudioRaiseVolume", "\tkeycode: 0",
            "\tcatchall: false", "\tdescription: volume up", "\tdispatcher: __lua", "\targ: 12", "",
        ]
        .join("\n");
        let parsed = parse_hyprland_binds(&text);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].chord, "XF86AudioRaiseVolume");
        assert_eq!(parsed[0].action, "");
        assert_eq!(parsed[0].args.len(), 0);
        assert_eq!(describe_action(&parsed[0]), "volume up");
    }

    #[test]
    fn props_carry_the_fields_the_table_reports() {
        let b = binds();
        assert_eq!(b[0].props.submap, "");
        assert_eq!(b[0].props.catchall, "false");
    }

    #[test]
    fn keycode_only_bind_reads_as_a_code_chord() {
        let text = [
            "bind", "\tmodmask: 0", "\tsubmap: scratch", "\tkey: ", "\tkeycode: 24", "\tcatchall: true",
            "\tdescription: ", "\tdispatcher: exec", "\targ: x",
        ]
        .join("\n");
        let parsed = parse_hyprland_binds(&text);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].chord, "code:24");
        assert_eq!(parsed[0].props.submap, "scratch");
        assert_eq!(parsed[0].props.catchall, "true");
    }

    #[test]
    fn malformed_input_never_panics() {
        assert_eq!(parse_hyprland_binds("").len(), 0);
        assert_eq!(parse_hyprland_binds("Invalid command").len(), 0);
        assert_eq!(parse_hyprland_binds("{\"binds\": []}").len(), 0);
        let partial = parse_hyprland_binds("bind\n\tmodmask: 64\n\tkey: A\n\tdispatcher: exec");
        assert_eq!(partial.len(), 1);
        assert_eq!(partial[0].chord, "SUPER+A");
    }

    #[test]
    fn describe_action_joins_action_and_args() {
        let b = binds();
        assert_eq!(describe_action(&b[0]), "exec hyprctl version");
        assert_eq!(describe_action(&b[2]), "killactive");
    }

    #[test]
    fn rows_shape() {
        let rows = rows(&binds(), "");
        assert_eq!(rows.len(), 5);
        assert_eq!(rows[1].kind, "note");
        assert_eq!(rows[1].dim, None);
        assert_eq!(rows[1].icon, "");
        assert!(rows[1].label.starts_with("SUPER+T"));
        assert_eq!(rows[1].desc, "exec ghostty");
        let mut ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), 5);
    }

    fn bare(chord: &str, action: &str) -> Bind {
        Bind { chord: chord.into(), action: action.into(), ..Default::default() }
    }

    #[test]
    fn rows_ids_survive_duplicate_chords() {
        let rows = rows(&[bare("SUPER+A", "a"), bare("SUPER+A", "b")], "");
        assert_eq!(rows[0].id, "keybinds.0.SUPER+A");
        assert_eq!(rows[1].id, "keybinds.1.SUPER+A");
    }

    #[test]
    fn rows_pad_chords_into_a_column() {
        let b = binds();
        let rows = rows(&b, "");
        let width = rows[0].label.chars().count();
        assert_eq!(width, "SUPER+SHIFT+slash".len());
        for (row, bind) in rows.iter().zip(&b) {
            assert_eq!(row.label.chars().count(), width);
            assert_eq!(js::trim(&row.label), bind.chord);
        }
    }

    #[test]
    fn search_tiers_and_order() {
        let b = binds();
        assert_eq!(chords(&search(&b, "exec")), "SUPER+SHIFT+slash SUPER+T SUPER+N");
        assert_eq!(search(&b, "SUPER+Q")[0].chord, "SUPER+Q");
        assert_eq!(chords(&search(&b, "notify")), "SUPER+N");
        assert_eq!(chords(&search(&b, "workspace")), "SUPER+CTRL+1");
        assert_eq!(search(&b, "zzz").len(), 0);
        assert_eq!(search(&b, "").len(), 5);
    }

    #[test]
    fn trigger_query_cases() {
        assert_eq!(trigger_query(":k close"), Some("close".into()));
        assert_eq!(trigger_query(":k "), Some(String::new()));
        assert_eq!(trigger_query(":k"), Some(String::new()));
        assert_eq!(trigger_query("keys"), None);
        assert_eq!(trigger_query(":keys"), None);
        assert_eq!(trigger_query(""), None);
    }

    #[test]
    fn note_rows_are_honest() {
        let notes = [no_binds_row(), failed_row()];
        assert_eq!(notes[0].label, "No binds");
        assert_eq!(notes[1].label, "Binds unavailable");
        for n in &notes {
            assert_eq!(n.kind, "note");
            assert_eq!(n.dim, Some(true));
            assert_eq!(n.icon, "");
            assert!(!n.desc.is_empty());
        }
        assert_ne!(notes[0].id, notes[1].id);
    }
}
