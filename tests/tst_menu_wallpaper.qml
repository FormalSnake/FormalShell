import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The root "wallpaper" node and the rows its level shows (M23). The picker
// used to be a Panel popout reached by a spawned `picker summon` action, so
// this node used to be injected from JS with the running shell's own path
// baked into it (providers.wallpaperEntry, deleted). It is a menu ROUTE
// now — an ordinary provider entry that default-menu.jsonc can declare
// itself, whose level Menu.qml renders as a grid of Providers.imageRows.
//
// Loads the real shipped default-menu.jsonc rather than a fixture mirroring
// it: the point is that the declaration in the file the package ships still
// builds the route the menu and the `picker` IPC target both resolve
// against. Reading a file outside the test's own directory needs
// QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner invocations in
// justfile and flake.nix's qml-tests derivation (tst_menu_emoji.qml does
// the same for emoji.json).
TestCase {
    name: "MenuWallpaper"

    property var defaultObj: ({})

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../shell/Menu/default-menu.jsonc"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        defaultObj = Model.parseJsonc(xhr.responseText);
    }

    function test_shipped_default_declares_the_wallpaper_route() {
        var entry = defaultObj["wallpaper"];
        verify(entry);
        compare(entry.label, "Wallpaper");
        compare(entry.provider, "wallpaper");
        verify(entry.icon.length > 0);
        verify(entry.aliases.indexOf("picker") >= 0);
    }

    // "provider" is what makes the node a descendable level rather than an
    // action row — Menu.qml's _activateRow enters it, and _displayRows
    // swaps the row list for the image grid once currentNodeId is it.
    function test_it_builds_as_a_root_provider_level() {
        var tree = Model.buildTree(defaultObj, {});
        var node = tree.nodes["wallpaper"];
        verify(node);
        compare(node.parentId, null);
        compare(node.kind, "provider");
        verify(tree.rootIds.indexOf("wallpaper") >= 0);
    }

    // No provider fn is registered for it (same as emoji/nix/calc/keybinds):
    // the level's contents come from the directory scan, not the tree, so
    // the node stays childless after applyProviders rather than silently
    // acquiring rows from somewhere else.
    function test_no_provider_fn_leaves_the_level_childless() {
        var tree = Providers.applyProviders(Model.buildTree(defaultObj, {}), {});
        compare(tree.nodes["wallpaper"].childIds.length, 0);
    }

    function test_user_overlay_can_hide_it() {
        var tree = Model.buildTree({ "wallpaper": defaultObj["wallpaper"] }, { "wallpaper": { hidden: true } });
        verify(!tree.nodes["wallpaper"]);
        compare(tree.rootIds.length, 0);
    }

    function test_image_rows_carry_the_path_and_a_basename_label() {
        var rows = Providers.imageRows(["/pics/aurora.png", "/pics/dune.jpg"], "");
        compare(rows.length, 2);
        compare(rows[0].kind, "image");
        compare(rows[0].path, "/pics/aurora.png");
        compare(rows[0].label, "aurora.png");
        compare(rows[0].parentId, "wallpaper");
    }

    // Filtering is on the basename only: every row in a listing shares the
    // same directory component, so matching it would make any query that
    // happens to contain a directory name match the whole listing.
    function test_image_rows_filter_on_the_basename_not_the_directory() {
        var paths = ["/home/kyan/dune/aurora.png", "/home/kyan/dune/dune.jpg"];
        compare(Providers.imageRows(paths, "dune").length, 1);
        compare(Providers.imageRows(paths, "dune")[0].path, "/home/kyan/dune/dune.jpg");
        compare(Providers.imageRows(paths, "AURORA").length, 1);
        compare(Providers.imageRows(paths, "").length, 2);
    }

    function test_image_rows_tolerate_an_empty_listing() {
        compare(Providers.imageRows([], "").length, 0);
        compare(Providers.imageRows(null, "x").length, 0);
    }
}
