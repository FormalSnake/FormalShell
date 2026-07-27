import QtQuick
import QtTest
import "../shell/Menu/model.js" as M
import "../shell/Menu/search.js" as S

TestCase {
    name: "MenuSearch"

    function test_score_tier_ordering() {
        // depth 3 keeps every case clear of the root bonus so only the
        // tier value itself is under test.
        compare(S.score({ id: "a", label: "Files", aliases: [], title: "" }, "files", 3, 0), 1000);
        compare(S.score({ id: "a", label: "Filesystem", aliases: [], title: "" }, "files", 3, 0), 800);
        compare(S.score({ id: "a", label: "My Files Manager", aliases: [], title: "" }, "files", 3, 0), 600);
        compare(S.score({ id: "a", label: "Documents", aliases: ["files"], title: "" }, "files", 3, 0), 400);
        compare(S.score({ id: "quick.files", label: "Documents", aliases: [], title: "" }, "files", 3, 0), 400);
        compare(S.score({ id: "a", label: "Browser", aliases: [], title: "Open your files here" }, "files", 3, 0), 200);
        compare(S.score({ id: "a", label: "Browser", aliases: [], title: "nothing relevant" }, "files", 3, 0), 0);
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
        compare(S.score(node, "files", 0, 0), 1100);
        compare(S.score(node, "files", 1, 0), 1000);
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
        compare(S.score(appNode, "files", 3, 0), 950);
        verify(S.score(appNode, "files", 3, 0) < S.score(menuNode, "files", 3, 0));
        // ...but a demoted exact-tier app still outranks a menu row one
        // full tier down (the demotion never crosses a tier boundary).
        var startsWithNode = { id: "c", label: "Filesystem", aliases: [], title: "" };
        verify(S.score(appNode, "files", 3, 0) > S.score(startsWithNode, "files", 3, 0));
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
