import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The injected root "wallpaper" node (M13 Task 5): providers.wallpaperEntry
// produces a jsonc-shaped fragment Menu.qml merges into the default tree
// object before buildTree, so it behaves like any declared node — root
// placement, action kind, per-key user override and hidden all apply.
TestCase {
    name: "MenuWallpaper"

    function test_entry_shape_carries_self_targeting_picker_summon() {
        var entry = Providers.wallpaperEntry("/store/share/formalshell");
        var node = entry["wallpaper"];
        verify(node);
        compare(node.label, "Wallpaper");
        verify(node.icon.length > 0);
        compare(node.action, "qs ipc -p /store/share/formalshell call picker summon");
    }

    function test_merged_entry_builds_a_root_action_node() {
        var def = { "theme": { label: "Theme", action: "true" } };
        var entry = Providers.wallpaperEntry("/self");
        Object.keys(entry).forEach(function (k) { def[k] = entry[k]; });
        var tree = Model.buildTree(def, {});
        var node = tree.nodes["wallpaper"];
        verify(node);
        compare(node.parentId, null);
        compare(node.kind, "action");
        verify(tree.rootIds.indexOf("wallpaper") >= 0);
    }

    function test_user_overlay_can_hide_it() {
        var def = Providers.wallpaperEntry("/self");
        var tree = Model.buildTree(def, { "wallpaper": { hidden: true } });
        verify(!tree.nodes["wallpaper"]);
        compare(tree.rootIds.length, 0);
    }
}
