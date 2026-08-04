import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The injected "system.stay-awake" node (M-polish batch item B):
// providers.stayAwakeEntry produces a jsonc-shaped fragment Menu.qml merges
// into the default tree object before buildTree, mirroring
// tst_menu_wallpaper.qml's own wallpaperEntry coverage — dotted id
// auto-nesting under the already-declared "system" node, action kind, and
// user override/hidden all apply the same way.
TestCase {
    name: "MenuStayAwake"

    function test_entry_shape_carries_self_targeting_screensaver_toggle() {
        var entry = Providers.stayAwakeEntry("/store/share/formalshell");
        var node = entry["system.stay-awake"];
        verify(node);
        compare(node.label, "Stay Awake");
        verify(node.icon.length > 0);
        compare(node.action, "qs ipc --any-display -p /store/share/formalshell call screensaver stayAwakeToggle");
    }

    function test_merged_entry_auto_nests_under_system() {
        var def = { "system": { label: "System" } };
        var entry = Providers.stayAwakeEntry("/self");
        Object.keys(entry).forEach(function (k) { def[k] = entry[k]; });
        var tree = Model.buildTree(def, {});
        var node = tree.nodes["system.stay-awake"];
        verify(node);
        compare(node.parentId, "system");
        compare(node.kind, "action");
        verify(tree.nodes["system"].childIds.indexOf("system.stay-awake") >= 0);
    }

    function test_user_overlay_can_hide_it() {
        var def = { "system": { label: "System" } };
        var entry = Providers.stayAwakeEntry("/self");
        Object.keys(entry).forEach(function (k) { def[k] = entry[k]; });
        var tree = Model.buildTree(def, { "system.stay-awake": { hidden: true } });
        verify(!tree.nodes["system.stay-awake"]);
    }
}
