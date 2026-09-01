import QtQuick
import QtTest
import "../shell/Menu/model.js" as M
import "../shell/Menu/search.js" as S

TestCase {
    name: "MenuSearch"

    function test_score_tier_ordering() {
        // depth 3 keeps every case clear of the root bonus so only the
        // tier value itself is under test. "files" slugs to itself, so the
        // query and its slug are the same literal here.
        compare(S.score({ id: "a", label: "Files", aliases: [], title: "" }, "files", "files", 3), 1000);
        compare(S.score({ id: "a", label: "Filesystem", aliases: [], title: "" }, "files", "files", 3), 800);
        compare(S.score({ id: "a", label: "My Files Manager", aliases: [], title: "" }, "files", "files", 3), 600);
        compare(S.score({ id: "a", label: "Documents", aliases: ["files"], title: "" }, "files", "files", 3), 400);
        compare(S.score({ id: "quick.files", label: "Documents", aliases: [], title: "" }, "files", "files", 3), 400);
        compare(S.score({ id: "a", label: "Browser", aliases: [], title: "Open your files here" }, "files", "files", 3), 200);
        compare(S.score({ id: "a", label: "Browser", aliases: [], title: "nothing relevant" }, "files", "files", 3), 0);
    }

    // A6: the alias tier slugs the node's OWN id (parentId stripped), never
    // the full dotted id. A provider route's own prefix ("apps.") would
    // otherwise leak into every one of its rows' alias match, which is what
    // made a single letter like "p" alias-match nearly every installed app.
    function test_alias_tier_ignores_the_parent_route_prefix() {
        var node = { id: "apps.org.mozilla.firefox", parentId: "apps", label: "Firefox", aliases: [], title: "" };
        // "p" is only in "apps", never in "org.mozilla.firefox".
        compare(S.score(node, "p", "p", 3), 0);
        compare(S.score(node, "moz", "moz", 3), 400);
    }

    function test_score_tiers_rank_in_declared_order() {
        var def = {
            "exact": { label: "Files" },
            "starts": { label: "Filesystem" },
            "contains": { label: "My Files Manager" },
            "alias": { label: "Documents", aliases: ["files"] },
            "title": { label: "Browser", title: "Open your files here" }
        };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "files", {});
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["exact", "starts", "contains", "alias", "title"]);
    }

    function test_score_root_bonus() {
        var node = { id: "a", label: "Files", aliases: [], title: "" };
        compare(S.score(node, "files", "files", 0), 1100);
        compare(S.score(node, "files", "files", 1), 1000);
    }

    function test_rank_root_bonus_orders_before_deeper_exact_match() {
        var def = {
            "reboot": { label: "Reboot" },
            "system.power.reboot": { label: "Reboot" }
        };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "Reboot", {});
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["reboot", "system.power.reboot"]);
    }

    function test_rank_ties_break_by_shallower_depth() {
        var def = {
            "b.match": { label: "Power Settings" },
            "a.deep1.match": { label: "Power Settings" }
        };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "Power Settings", {});
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["b.match", "a.deep1.match"]);
    }

    function test_rank_ties_break_by_declaration_order() {
        var def = {
            "second": { label: "Task" },
            "first": { label: "Task" }
        };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "Task", {});
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["second", "first"]);
    }

    function test_score_app_kind_demotes_within_its_own_tier() {
        var appNode = { id: "a", label: "Files", aliases: [], title: "", kind: "app" };
        var menuNode = { id: "b", label: "Files", aliases: [], title: "" };
        compare(S.score(appNode, "files", "files", 3), 950);
        verify(S.score(appNode, "files", "files", 3) < S.score(menuNode, "files", "files", 3));
        // ...but a demoted exact-tier app still outranks a menu row one
        // full tier down (the demotion never crosses a tier boundary).
        var startsWithNode = { id: "c", label: "Filesystem", aliases: [], title: "" };
        verify(S.score(appNode, "files", "files", 3) > S.score(startsWithNode, "files", "files", 3));
    }

    // routeOnly: a route whose provider names its rows after things the
    // launcher already lists elsewhere (the tray, the panels) is walked
    // only from inside itself, so a root query returns the app once.
    function _routeOnlyTree() {
        return M.buildTree({
            "apps": {},
            "apps.equibop": { label: "Equibop" },
            "tray": { label: "Tray", "routeOnly": true },
            "tray.equibop": { label: "Equibop" }
        }, {});
    }

    function test_route_only_subtree_is_invisible_to_a_root_query() {
        var ranked = S.rank(_routeOnlyTree().nodes, "Equibop", {}, null);
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["apps.equibop"]);
    }

    function test_route_only_subtree_is_searchable_from_inside_the_route() {
        var ranked = S.rank(_routeOnlyTree().nodes, "Equibop", {}, "tray");
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["apps.equibop", "tray.equibop"]);
    }

    // The route row itself is not what routeOnly hides, so the route stays
    // reachable by name from the root the way every other route is.
    function test_route_only_route_row_still_matches_from_the_root() {
        var ranked = S.rank(_routeOnlyTree().nodes, "Tray", {}, null);
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["tray"]);
    }

    // The score picks the cut and which group leads; the group picks
    // where a row lands. Bonfire (600) comes out above Firefox (750)
    // because System's best hit outscored Apps' best hit, and the exact
    // clipboard match still heads the whole list.
    function test_rank_deals_the_cut_out_by_root_route() {
        var def = {
            "apps": { provider: "apps" },
            "apps.firefox": { label: "Firefox", kind: "app" },
            "apps.campfire": { label: "Campfire", kind: "app" },
            "system": {},
            "system.firewall": { label: "Firewall" },
            "system.bonfire": { label: "Bonfire" },
            "clipboard": { provider: "clipboard" },
            "clipboard.1": { label: "fire" }
        };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "fire", {});
        var ids = ranked.map(function (n) { return n.id; });
        compare(ids, ["clipboard.1", "system.firewall", "system.bonfire", "apps.firefox", "apps.campfire"]);
    }

    // Grouping happens after the cap, so it can only reorder the forty
    // best rows, never let a weaker row in on the strength of its group.
    function test_rank_groups_after_the_cap() {
        var def = { "top": {} };
        for (var i = 0; i < 40; i++) {
            def["top.item" + i] = { label: "Item " + i };
        }
        def["other"] = {};
        def["other.item"] = { label: "Item last" };
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "item", {});
        compare(ranked.length, 40);
        verify(ranked.every(function (n) { return n.parentId === "top"; }));
    }

    function test_rank_caps_at_forty() {
        var def = {};
        for (var i = 0; i < 45; i++) {
            def["item" + i] = { label: "Item " + i };
        }
        var tree = M.buildTree(def, {});
        var ranked = S.rank(tree.nodes, "item", {});
        compare(ranked.length, 40);
    }
}
