mod common;

use common::*;
use fs_menu::node::{Kind, Node, Tree};
use fs_menu::search::{self, score};
use serde_json::json;

fn node(id: &str, label: &str) -> Node {
    Node::new(id, label, Kind::Submenu)
}

// depth 3 keeps every case clear of the root bonus so only the tier value
// itself is under test. "files" slugs to itself, so the query and its slug
// are the same literal here.
#[test]
fn score_tier_ordering() {
    let s = |n: &Node| score(n, "files", "files", 3);
    assert_eq!(s(&node("a", "Files")), 1000);
    assert_eq!(s(&node("a", "Filesystem")), 800);
    assert_eq!(s(&node("a", "My Files Manager")), 600);
    assert_eq!(s(&Node { aliases: vec!["files".into()], ..node("a", "Documents") }), 400);
    assert_eq!(s(&node("quick.files", "Documents")), 400);
    assert_eq!(s(&Node { title: "Open your files here".into(), ..node("a", "Browser") }), 200);
    assert_eq!(s(&Node { title: "nothing relevant".into(), ..node("a", "Browser") }), 0);
}

// The alias tier slugs the node's OWN id (parentId stripped), never the full
// dotted id. A provider route's own prefix ("apps.") would otherwise leak into
// every one of its rows' alias match, which is what made a single letter like
// "p" alias-match nearly every installed app.
#[test]
fn alias_tier_ignores_the_parent_route_prefix() {
    let n = Node { parent_id: Some("apps".into()), ..node("apps.org.mozilla.firefox", "Firefox") };
    // "p" is only in "apps", never in "org.mozilla.firefox".
    assert_eq!(score(&n, "p", "p", 3), 0);
    assert_eq!(score(&n, "moz", "moz", 3), 400);
}

fn ranked_ids(tree: &Tree, query: &str, within: Option<&str>) -> Vec<String> {
    search::rank(&tree.nodes, query, &no_conds(), within).iter().map(|n| n.id.clone()).collect()
}

#[test]
fn score_tiers_rank_in_declared_order() {
    let tree = tree_of(json!({
        "exact": { "label": "Files" },
        "starts": { "label": "Filesystem" },
        "contains": { "label": "My Files Manager" },
        "alias": { "label": "Documents", "aliases": ["files"] },
        "title": { "label": "Browser", "title": "Open your files here" }
    }));
    assert_eq!(ranked_ids(&tree, "files", None), ["exact", "starts", "contains", "alias", "title"]);
}

#[test]
fn score_root_bonus() {
    let n = node("a", "Files");
    assert_eq!(score(&n, "files", "files", 0), 1100);
    assert_eq!(score(&n, "files", "files", 1), 1000);
}

#[test]
fn rank_root_bonus_orders_before_deeper_exact_match() {
    let tree = tree_of(json!({
        "reboot": { "label": "Reboot" },
        "system.power.reboot": { "label": "Reboot" }
    }));
    assert_eq!(ranked_ids(&tree, "Reboot", None), ["reboot", "system.power.reboot"]);
}

#[test]
fn rank_ties_break_by_shallower_depth() {
    let tree = tree_of(json!({
        "b.match": { "label": "Power Settings" },
        "a.deep1.match": { "label": "Power Settings" }
    }));
    assert_eq!(ranked_ids(&tree, "Power Settings", None), ["b.match", "a.deep1.match"]);
}

#[test]
fn rank_ties_break_by_declaration_order() {
    let tree = tree_of(json!({ "second": { "label": "Task" }, "first": { "label": "Task" } }));
    assert_eq!(ranked_ids(&tree, "Task", None), ["second", "first"]);
}

#[test]
fn score_app_kind_demotes_within_its_own_tier() {
    let app = Node::new("a", "Files", Kind::App);
    let menu = node("b", "Files");
    assert_eq!(score(&app, "files", "files", 3), 950);
    assert!(score(&app, "files", "files", 3) < score(&menu, "files", "files", 3));
    // ...but a demoted exact-tier app still outranks a menu row one full tier
    // down (the demotion never crosses a tier boundary).
    let starts_with = node("c", "Filesystem");
    assert!(score(&app, "files", "files", 3) > score(&starts_with, "files", "files", 3));
}

// routeOnly: a route whose provider names its rows after things the launcher
// already lists elsewhere (the tray) is walked only from inside itself, so a
// root query returns the app once.
fn route_only_tree() -> Tree {
    tree_of(json!({
        "apps": {},
        "apps.equibop": { "label": "Equibop" },
        "tray": { "label": "Tray", "routeOnly": true },
        "tray.equibop": { "label": "Equibop" }
    }))
}

#[test]
fn route_only_subtree_is_invisible_to_a_root_query() {
    assert_eq!(ranked_ids(&route_only_tree(), "Equibop", None), ["apps.equibop"]);
}

#[test]
fn route_only_subtree_is_searchable_from_inside_the_route() {
    assert_eq!(ranked_ids(&route_only_tree(), "Equibop", Some("tray")), ["apps.equibop", "tray.equibop"]);
}

// localOnly is set on the built node: only provider rows carry it, and
// build_tree copies a fixed key list.
fn local_only_tree() -> Tree {
    let mut tree = tree_of(json!({
        "net": { "label": "Net" },
        "net.home": { "label": "Cafe Home" },
        "net.scan": { "label": "Cafe Scan" }
    }));
    tree.nodes["net.scan"].local_only = true;
    tree
}

#[test]
fn local_only_child_is_absent_from_a_root_query() {
    assert_eq!(ranked_ids(&local_only_tree(), "Cafe", None), ["net.home"]);
}

#[test]
fn local_only_child_is_found_inside_its_parent() {
    let mut ids = ranked_ids(&local_only_tree(), "Cafe", Some("net"));
    ids.sort();
    assert_eq!(ids, ["net.home", "net.scan"]);
}

// The route row itself is not what routeOnly hides, so the route stays
// reachable by name from the root the way every other route is.
#[test]
fn route_only_route_row_still_matches_from_the_root() {
    assert_eq!(ranked_ids(&route_only_tree(), "Tray", None), ["tray"]);
}

// The score picks the cut and which group leads; the group picks where a row
// lands. Bonfire (600) comes out above Firefox (750) because System's best hit
// outscored Apps' best hit, and the exact clipboard match still heads the
// whole list.
#[test]
fn rank_deals_the_cut_out_by_root_route() {
    let tree = tree_of(json!({
        "apps": { "provider": "apps" },
        "apps.firefox": { "label": "Firefox", "kind": "app" },
        "apps.campfire": { "label": "Campfire", "kind": "app" },
        "system": {},
        "system.firewall": { "label": "Firewall" },
        "system.bonfire": { "label": "Bonfire" },
        "clipboard": { "provider": "clipboard" },
        "clipboard.1": { "label": "fire" }
    }));
    assert_eq!(
        ranked_ids(&tree, "fire", None),
        ["clipboard.1", "system.firewall", "system.bonfire", "apps.firefox", "apps.campfire"]
    );
}

// Grouping happens after the cap, so it can only reorder the forty best rows,
// never let a weaker row in on the strength of its group.
#[test]
fn rank_groups_after_the_cap() {
    let mut def = serde_json::Map::new();
    def.insert("top".into(), json!({}));
    for i in 0..40 {
        def.insert(format!("top.item{i}"), json!({ "label": format!("Item {i}") }));
    }
    def.insert("other".into(), json!({}));
    def.insert("other.item".into(), json!({ "label": "Item last" }));
    let tree = tree_of(serde_json::Value::Object(def));
    let ranked = search::rank(&tree.nodes, "item", &no_conds(), None);
    assert_eq!(ranked.len(), 40);
    assert!(ranked.iter().all(|n| n.parent_id.as_deref() == Some("top")));
}

#[test]
fn rank_caps_at_forty() {
    let mut def = serde_json::Map::new();
    for i in 0..45 {
        def.insert(format!("item{i}"), json!({ "label": format!("Item {i}") }));
    }
    let tree = tree_of(serde_json::Value::Object(def));
    assert_eq!(search::rank(&tree.nodes, "item", &no_conds(), None).len(), 40);
}
