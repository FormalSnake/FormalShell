import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers
import "../shell/Menu/actions.js" as Actions

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

    // Dark/Light variants (owner, 2026-08-12). The scan hands over the
    // picker directory AND its Dark/Light subdirectories in one listing;
    // this is the split the route's switcher reads.
    function test_variants_split_the_listing_by_subdirectory() {
        var v = Providers.wallpaperVariants([
            "/pics/Dark/night.png",
            "/pics/Light/day.png",
            "/pics/Light/noon.jpg"
        ], "/pics");
        verify(v.hasVariants);
        compare(v.dark.length, 1);
        compare(v.light.length, 2);
        compare(v.root.length, 0);
        compare(v.dark[0], "/pics/Dark/night.png");
    }

    // Either case, since the owner's own directories may be either and a
    // case-insensitive filesystem makes the distinction meaningless anyway.
    function test_variant_directory_names_are_case_insensitive() {
        var v = Providers.wallpaperVariants([
            "/pics/dark/night.png",
            "/pics/LIGHT/day.png"
        ], "/pics");
        compare(v.dark.length, 1);
        compare(v.light.length, 1);
    }

    // No subdirectory pair: one flat listing, no switcher, exactly the
    // behavior every existing setup has today.
    function test_a_directory_without_the_pair_lists_flat() {
        var v = Providers.wallpaperVariants(["/pics/a.png", "/pics/b.png"], "/pics");
        verify(!v.hasVariants);
        compare(v.root.length, 2);
        compare(v.dark.length, 0);
        compare(v.light.length, 0);
    }

    // Classification is by position relative to the scanned directory, not
    // by the parent directory's name: a picker directory that is itself
    // called Dark must not turn its own root listing into a variant.
    function test_a_base_directory_named_dark_is_still_the_root_listing() {
        var v = Providers.wallpaperVariants(["/pics/Dark/night.png"], "/pics/Dark");
        verify(!v.hasVariants);
        compare(v.root.length, 1);
    }

    // Any other subdirectory is neither variant: only the two names mean
    // anything, and a directory of, say, archived wallpapers must not become
    // one mode's set. The scan's own -maxdepth 1 means neither case reaches
    // here in practice; the rule is the first path segment either way, so
    // something nested under Dark/ would still be dark rather than unsorted.
    function test_unrelated_subdirectories_are_not_variants() {
        var v = Providers.wallpaperVariants(["/pics/archive/old.png"], "/pics");
        verify(!v.hasVariants);
        compare(v.root.length, 1);

        var nested = Providers.wallpaperVariants(["/pics/Dark/deep/deeper.png"], "/pics");
        compare(nested.dark.length, 1);
    }

    // One variant present is still variant mode: the empty side reads
    // honestly under its own header, where falling back to the root listing
    // would look like the switcher did nothing.
    function test_one_variant_alone_still_raises_the_switcher() {
        var v = Providers.wallpaperVariants(["/pics/Dark/night.png"], "/pics");
        verify(v.hasVariants);
        compare(Providers.wallpaperListing(v, "light").length, 0);
        compare(Providers.wallpaperListing(v, "dark").length, 1);
    }

    // The one function the grid, `picker choose`'s membership check and
    // `picker status`'s count all read, so they cannot disagree about what is
    // on screen. An unknown variant name resolves to dark rather than to
    // nothing.
    function test_listing_picks_the_variant_or_the_flat_root() {
        var pair = Providers.wallpaperVariants(["/pics/Dark/n.png", "/pics/Light/d.png"], "/pics");
        compare(Providers.wallpaperListing(pair, "dark")[0], "/pics/Dark/n.png");
        compare(Providers.wallpaperListing(pair, "light")[0], "/pics/Light/d.png");
        compare(Providers.wallpaperListing(pair, "")[0], "/pics/Dark/n.png");

        var flat = Providers.wallpaperVariants(["/pics/a.png"], "/pics");
        compare(Providers.wallpaperListing(flat, "light")[0], "/pics/a.png");
    }

    function test_variants_tolerate_an_empty_scan() {
        var v = Providers.wallpaperVariants([], "/pics");
        verify(!v.hasVariants);
        compare(Providers.wallpaperListing(v, "dark").length, 0);
        compare(Providers.wallpaperVariants(null, "").root.length, 0);
    }

    // The action bar names the set Tab would show, and only while the
    // switcher is actually up (Menu/actions.js).
    function test_the_action_bar_offers_tab_only_where_variants_exist() {
        var withVariants = Actions.hints({ mode: "menu", grid: true, variantSwitch: "light" });
        var tab = withVariants.filter(function (h) { return h.key === "TAB"; });
        compare(tab.length, 1);
        compare(tab[0].label, "Show Light");

        var flat = Actions.hints({ mode: "menu", grid: true, variantSwitch: null });
        compare(flat.filter(function (h) { return h.key === "TAB"; }).length, 0);
    }
}
