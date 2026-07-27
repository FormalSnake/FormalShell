import QtQuick
import QtTest
import "../shell/Menu/model.js" as M

TestCase {
    name: "MenuModel"

    function test_dotted_id_hierarchy_with_auto_parents() {
        var def = {
            "system.power.reboot": { label: "Reboot", action: "systemctl reboot" }
        };
        var tree = M.buildTree(def, {});
        compare(tree.rootIds.length, 1);
        compare(tree.rootIds[0], "system");

        var system = tree.nodes["system"];
        verify(system);
        compare(system.kind, "submenu");
        compare(system.parentId, null);
        compare(system.label, "System");
        compare(system.childIds.length, 1);
        compare(system.childIds[0], "system.power");

        var power = tree.nodes["system.power"];
        verify(power);
        compare(power.kind, "submenu");
        compare(power.parentId, "system");
        compare(power.label, "Power");
        compare(power.childIds.length, 1);
        compare(power.childIds[0], "system.power.reboot");

        var reboot = tree.nodes["system.power.reboot"];
        verify(reboot);
        compare(reboot.parentId, "system.power");
        compare(reboot.label, "Reboot");
        compare(reboot.childIds.length, 0);
    }

    function test_kind_inference_for_all_four_kinds() {
        var def = {
            "a": { label: "Action", action: "echo hi" },
            "b": { label: "Link", target: "a" },
            "c": { label: "Provider", provider: "apps" },
            "d": { label: "Submenu" }
        };
        var tree = M.buildTree(def, {});
        compare(tree.nodes["a"].kind, "action");
        compare(tree.nodes["a"].action, "echo hi");
        compare(tree.nodes["b"].kind, "link");
        compare(tree.nodes["b"].target, "a");
        compare(tree.nodes["c"].kind, "provider");
        compare(tree.nodes["c"].provider, "apps");
        compare(tree.nodes["d"].kind, "submenu");
    }

    function test_user_override_of_default_label() {
        var def = { "apps": { label: "Applications", icon: "" } };
        var user = { "apps": { label: "My Apps" } };
        var tree = M.buildTree(def, user);
        compare(tree.nodes["apps"].label, "My Apps");
    }

    function test_hidden_removes_a_subtree() {
        var def = {
            "system": { label: "System" },
            "system.power": { label: "Power" },
            "system.power.reboot": { label: "Reboot", action: "systemctl reboot" }
        };
        var user = { "system.power": { hidden: true } };
        var tree = M.buildTree(def, user);
        verify(!tree.nodes["system.power"]);
        verify(!tree.nodes["system.power.reboot"]);
        verify(tree.nodes["system"]);
        compare(tree.nodes["system"].childIds.length, 0);
    }

    function test_self_pruning_cascade() {
        var def = {
            "system": { label: "System" },
            "system.power": { label: "Power" },
            "system.power.reboot": { label: "Reboot", action: "systemctl reboot", when: "false" }
        };
        var tree = M.buildTree(def, {});
        var cond = { "system.power.reboot": false };
        // the leaf itself is hidden by its condition...
        compare(M.visibleChildren(tree.nodes, "system.power", cond).length, 0);
        // ...which empties its parent submenu...
        compare(M.visibleChildren(tree.nodes, "system", cond).length, 0);
        // ...which empties the root list.
        compare(M.visibleChildren(tree.nodes, null, cond).length, 0);
    }

    function test_visible_children_no_when_is_always_visible() {
        var def = {
            "apps": { label: "Apps", action: "true" },
            "system": { label: "System", action: "true" }
        };
        var tree = M.buildTree(def, {});
        var visible = M.visibleChildren(tree.nodes, null, {});
        compare(visible.length, 2);
    }

    function test_visible_children_when_true_shows_node() {
        var def = {
            "system": { label: "System" },
            "system.lock": { label: "Lock", action: "loginctl lock-session", when: "true" }
        };
        var tree = M.buildTree(def, {});
        var visible = M.visibleChildren(tree.nodes, "system", { "system.lock": true });
        compare(visible.length, 1);
        compare(visible[0].id, "system.lock");
    }

    function test_parse_jsonc_strips_line_comments_and_trailing_commas() {
        var text = [
            "{",
            "  // a leading comment",
            '  "a": 1,',
            '  "b": [1, 2, ],',
            "}"
        ].join("\n");
        var obj = M.parseJsonc(text);
        compare(obj.a, 1);
        compare(obj.b.length, 2);
        compare(obj.b[0], 1);
        compare(obj.b[1], 2);
    }

    function test_parse_jsonc_preserves_comment_like_text_inside_strings() {
        var text = '{ "note": "see http://example.com for // details, still here" }';
        var obj = M.parseJsonc(text);
        compare(obj.note, "see http://example.com for // details, still here");
    }

    function test_parse_jsonc_throws_on_hard_syntax_error() {
        var threw = false;
        try {
            M.parseJsonc('{ "a": }');
        } catch (e) {
            threw = true;
        }
        verify(threw);
    }
}
