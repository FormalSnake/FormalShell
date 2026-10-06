//! Omarchy-style tiered fuzzy scorer for the launcher's search field.
//!
//! Tiers sit 200 points apart so the root bonus (+100) and the app demotion
//! (-50) only reorder rows within a tier. The score picks which rows make the
//! cut and which group leads; the group picks where a row lands: the capped
//! list is dealt out by root route in the order each route's best hit earned.

use std::collections::{HashMap, HashSet};

use indexmap::IndexMap;

use crate::model::search_section_of;
use crate::node::{Kind, Node};

pub const TIER_EXACT: i32 = 1000;
pub const TIER_STARTS_WITH: i32 = 800;
pub const TIER_CONTAINS: i32 = 600;
pub const TIER_ALIAS: i32 = 400;
pub const TIER_TITLE: i32 = 200;
pub const ROOT_BONUS: i32 = 100;
pub const APP_DEMOTION: i32 = 50;
pub const MAX_RESULTS: usize = 40;

pub fn normalize(text: &str) -> String {
    text.to_lowercase()
}

pub fn slug(text: &str) -> String {
    normalize(text).chars().filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit()).collect()
}

/// True if any word in `text` starts with `needle`: "here" matches "Open
/// your files here" but "iles" does not.
pub fn word_boundary_match(text: &str, needle: &str) -> bool {
    normalize(text)
        .split(|c: char| !(c.is_ascii_lowercase() || c.is_ascii_digit()))
        .filter(|w| !w.is_empty())
        .any(|w| w.starts_with(needle))
}

/// The node's own identifier for the alias tier, with the parent's id prefix
/// stripped. A provider-built node's `parent_id` is the route's own id
/// ("apps") while the id itself can carry dots of its own, so splitting the
/// id on its last dot would cut it in the wrong place; stripping the parent
/// works for provider and jsonc nodes alike.
fn own_id(node: &Node) -> &str {
    match &node.parent_id {
        Some(parent) if !parent.is_empty() => {
            node.id.strip_prefix(parent.as_str()).and_then(|r| r.strip_prefix('.')).unwrap_or(&node.id)
        }
        _ => &node.id,
    }
}

/// `q_norm` and `q_slug` are the query normalized and slugged once by
/// `rank`, since a query is invariant across the whole tree walk.
pub fn score(node: &Node, q_norm: &str, q_slug: &str, depth: usize) -> i32 {
    if q_norm.is_empty() {
        return 0;
    }
    let label = normalize(&node.label);
    let mut tier = if label == q_norm {
        TIER_EXACT
    } else if label.starts_with(q_norm) {
        TIER_STARTS_WITH
    } else if label.contains(q_norm) {
        TIER_CONTAINS
    } else if node.aliases.iter().any(|a| normalize(a).contains(q_norm)) || slug(own_id(node)).contains(q_slug) {
        TIER_ALIAS
    } else if word_boundary_match(&node.title, q_norm) {
        TIER_TITLE
    } else {
        return 0;
    };
    if depth == 0 {
        tier += ROOT_BONUS;
    }
    if node.kind == Kind::App {
        tier -= APP_DEMOTION;
    }
    tier
}

/// The id itself plus every dotted prefix of it.
fn ancestry(id: Option<&str>) -> HashSet<String> {
    let mut out = HashSet::new();
    let mut prefix = String::new();
    for part in id.unwrap_or("").split('.') {
        if part.is_empty() {
            continue;
        }
        if !prefix.is_empty() {
            prefix.push('.');
        }
        prefix.push_str(part);
        out.insert(prefix.clone());
    }
    out
}

struct Hit<'a> {
    node: &'a Node,
    score: i32,
    depth: usize,
    decl_index: usize,
}

/// Depth-first walk of `nodes` from its roots, scoring every when-visible
/// node against `query` (a node whose `when` is not satisfied is skipped with
/// its whole subtree). Returns the 40 best matches (score, ties broken by
/// shallower depth then declaration order) grouped by root route, groups in
/// the order of their best hit, score order inside each.
///
/// `within_id` is the level the search runs from. It matters for a
/// `route_only` node, whose children are reachable only while standing
/// inside it (the tray names its items after applications that are already
/// listed). `local_only` is the per-node counterpart: scored only while the
/// node's parent level is open.
pub fn rank<'a>(
    nodes: &'a IndexMap<String, Node>,
    query: &str,
    cond_results: &HashMap<String, bool>,
    within_id: Option<&str>,
) -> Vec<&'a Node> {
    let open = ancestry(within_id);
    let q_norm = normalize(query);
    let q_slug = slug(&q_norm);
    let mut hits: Vec<Hit<'a>> = Vec::new();
    let mut decl_index = 0;

    struct Walk<'w, 'a> {
        nodes: &'a IndexMap<String, Node>,
        cond_results: &'w HashMap<String, bool>,
        open: &'w HashSet<String>,
        q_norm: &'w str,
        q_slug: &'w str,
    }

    fn visit<'a>(w: &Walk<'_, 'a>, id: &str, depth: usize, decl_index: &mut usize, hits: &mut Vec<Hit<'a>>) {
        let Some(node) = w.nodes.get(id) else { return };
        if node.when.is_some() && w.cond_results.get(&node.id) != Some(&true) {
            return;
        }
        let idx = *decl_index;
        *decl_index += 1;
        let parent_open = node.parent_id.as_ref().is_some_and(|p| w.open.contains(p));
        let s = if node.local_only && !parent_open { 0 } else { score(node, w.q_norm, w.q_slug, depth) };
        if s > 0 {
            hits.push(Hit { node, score: s, depth, decl_index: idx });
        }
        if node.route_only == Some(true) && !w.open.contains(id) {
            return;
        }
        for cid in &node.child_ids {
            visit(w, cid, depth + 1, decl_index, hits);
        }
    }

    let walk = Walk { nodes, cond_results, open: &open, q_norm: &q_norm, q_slug: &q_slug };
    for (id, node) in nodes {
        if node.parent_id.is_none() {
            visit(&walk, id, 0, &mut decl_index, &mut hits);
        }
    }

    hits.sort_by(|a, b| {
        b.score.cmp(&a.score).then(a.depth.cmp(&b.depth)).then(a.decl_index.cmp(&b.decl_index))
    });

    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, Vec<&'a Node>> = HashMap::new();
    for hit in hits.into_iter().take(MAX_RESULTS) {
        let key = search_section_of(Some(nodes), hit.node);
        if !groups.contains_key(&key) {
            order.push(key.clone());
        }
        groups.entry(key).or_default().push(hit.node);
    }
    order.iter().flat_map(|key| groups.remove(key).unwrap_or_default()).collect()
}
