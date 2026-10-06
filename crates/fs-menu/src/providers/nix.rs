//! The `:nix` runner's pure half: trigger parsing, `nix search --json` stdout
//! parsing, the exit-code to outcome mapping, and row building.

use serde_json::Value;

use super::clipboard::preview_label;
use crate::node::{Kind, Node};

pub const NIX_MAX_RESULTS: usize = 30;

/// `":nix"` root trigger: the package query after it, "" for the bare
/// `":nix"`, or `None` when `text` is not the trigger at all.
pub fn nix_trigger_query(text: &str) -> Option<&str> {
    if text == ":nix" {
        return Some("");
    }
    text.strip_prefix(":nix ")
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct NixResult {
    pub attr: String,
    pub version: String,
    pub description: String,
}

/// `String(entry.field || "")`: a falsy value reads as empty.
fn string_field(entry: &Value, key: &str) -> String {
    match entry.get(key) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) if n.as_f64() != Some(0.0) => n.to_string(),
        Some(Value::Bool(true)) => "true".to_string(),
        _ => String::new(),
    }
}

/// `nix search nixpkgs <q> --json` stdout, or `None` when the text is not a
/// JSON object at all: `nix_search_outcome` needs unparseable stdout (SEARCH
/// FAILED) kept distinct from nix's clean zero-hit `{}` answer (NO RESULTS).
/// Keys arrive as `legacyPackages.<system>.<attrpath>`; the first two dotted
/// components are the flake/system prefix `nix run nixpkgs#<attr>` must not
/// see, the remainder (itself possibly dotted: `python312Packages.requests`)
/// is the attr. Nix's own output order is kept.
pub fn parse_nix_search(text: &str) -> Option<Vec<NixResult>> {
    let obj: Value = serde_json::from_str(text).ok()?;
    let map = match &obj {
        Value::Object(map) => map,
        // An array is an object to JavaScript, and its numeric keys have no
        // attr in them: an empty result list, not a parse failure.
        Value::Array(_) => return Some(Vec::new()),
        _ => return None,
    };
    let mut out = Vec::new();
    for (key, entry) in map {
        let attr = key.split('.').skip(2).collect::<Vec<_>>().join(".");
        if attr.is_empty() {
            continue;
        }
        out.push(NixResult {
            attr,
            version: string_field(entry, "version"),
            description: string_field(entry, "description"),
        });
    }
    Some(out)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NixState {
    Unavailable,
    Failed,
    Empty,
    Results,
}

impl NixState {
    pub fn as_str(self) -> &'static str {
        match self {
            NixState::Unavailable => "unavailable",
            NixState::Failed => "failed",
            NixState::Empty => "empty",
            NixState::Results => "results",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct NixOutcome {
    pub state: NixState,
    pub results: Vec<NixResult>,
}

/// One finished search process to one honest end state: 127 is the `sh`
/// wrapper's missing-binary sentinel (NO NIX); any other non-zero exit or
/// unparseable stdout is SEARCH FAILED; a clean exit splits on whether the
/// parsed set has entries (results) or is nix's `{}` zero-hit answer (NO
/// RESULTS). Failure states never carry partial results.
pub fn nix_search_outcome(exit_code: i32, text: &str) -> NixOutcome {
    let none = |state| NixOutcome { state, results: Vec::new() };
    if exit_code == 127 {
        return none(NixState::Unavailable);
    }
    if exit_code != 0 {
        return none(NixState::Failed);
    }
    match parse_nix_search(text) {
        None => none(NixState::Failed),
        Some(results) if results.is_empty() => none(NixState::Empty),
        Some(results) => NixOutcome { state: NixState::Results, results },
    }
}

fn is_safe_attr(attr: &str) -> bool {
    !attr.is_empty() && attr.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '+' | '-'))
}

/// Search-result rows are plain "action" nodes, dispatched in-process
/// (`@ipc:nix.run:<attr>`): Enter runs the package in the quake console's own
/// terminal and placement, and closes. The attr still reaches a `sh -c`
/// string there, so anything outside the safe attr charset is skipped outright
/// rather than escaped; nixpkgs attrs are `[A-Za-z0-9._+-]` in practice.
/// `notify_summary` and `notify_body` mark the row for the activation toast:
/// the spawned terminal can be seconds from mapping, so Enter fires a
/// shell-local NIX RUN notification the moment it lands.
pub fn nix_rows(results: &[NixResult]) -> Vec<Node> {
    results
        .iter()
        .filter(|r| is_safe_attr(&r.attr))
        .take(NIX_MAX_RESULTS)
        .map(|r| Node {
            desc: Some(if r.description.is_empty() { String::new() } else { preview_label(&r.description, None) }),
            action: Some(format!("@ipc:nix.run:{}", r.attr)),
            notify_summary: Some("NIX RUN".to_string()),
            notify_body: Some(r.attr.clone()),
            ..Node::new(
                format!("nix.{}", r.attr),
                if r.version.is_empty() { r.attr.clone() } else { format!("{} {}", r.attr, r.version) },
                Kind::Action,
            )
        })
        .collect()
}

pub fn nix_unavailable_row() -> Node {
    Node::note("nix.unavailable", "Nix is not installed")
}

pub fn nix_indexing_row() -> Node {
    Node::note("nix.indexing", "Indexing nixpkgs")
}

pub fn nix_searching_row() -> Node {
    Node::note("nix.searching", "Searching")
}

pub fn nix_no_results_row() -> Node {
    Node::note("nix.noresults", "No results")
}

pub fn nix_failed_row() -> Node {
    Node::note("nix.failed", "Search failed")
}
