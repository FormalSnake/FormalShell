import QtQuick
import QtTest
import "../shell/Menu/appviews.js" as AppViews
import "../shell/Menu/model.js" as Model

// M38 Task 7, the launcher's app-view registry (plan decision D1). Two
// things are worth a test here: the lookup itself refuses everything it was
// not given, and the SHIPPED tree still lines up with it. The second is the
// one that would rot silently: renaming the "monitor" route in
// default-menu.jsonc without renaming its key in appviews.js leaves a route
// that opens perfectly and renders an empty row list, with nothing anywhere
// reporting a problem.
TestCase {
    name: "MenuAppViews"

    function _read(path) {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl(path));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        return xhr.responseText;
    }

    function test_registered_route_resolves_to_its_view() {
        compare(AppViews.viewFor("monitor"), "views/MonitorView.qml");
        compare(AppViews.isAppView("monitor"), true);
    }

    function test_unregistered_route_resolves_to_nothing() {
        compare(AppViews.viewFor("wallpaper"), "");
        compare(AppViews.viewFor("clipboard"), "");
        compare(AppViews.isAppView("apps"), false);
    }

    // Menu.qml calls viewFor(currentNodeId) on every level, and
    // currentNodeId is null at the root. Object-prototype keys matter for
    // the same reason: a bare `VIEWS[routeId]` lookup answers "constructor"
    // with a function, which is truthy, which would turn the root level of
    // anyone's menu into a broken app view.
    function test_garbage_input_resolves_to_nothing() {
        compare(AppViews.viewFor(null), "");
        compare(AppViews.viewFor(undefined), "");
        compare(AppViews.viewFor(""), "");
        compare(AppViews.viewFor(42), "");
        compare(AppViews.viewFor({}), "");
        compare(AppViews.viewFor("constructor"), "");
        compare(AppViews.viewFor("toString"), "");
        compare(AppViews.viewFor("__proto__"), "");
        compare(AppViews.isAppView("hasOwnProperty"), false);
    }

    // The drift guard: every registered id is a real node in the shipped
    // tree, and it is a "provider" node rather than a "submenu": a
    // childless submenu is filtered out of its parent level entirely
    // (model.js's visibleChildren), so an app-view route declared as one
    // would never appear as a row at all.
    function test_shipped_tree_carries_every_registered_route() {
        var tree = Model.buildTree(Model.parseJsonc(_read("../shell/Menu/default-menu.jsonc")), {});
        var ids = Object.keys(AppViews.VIEWS);
        verify(ids.length > 0);
        for (var i = 0; i < ids.length; i++) {
            var node = tree.nodes[ids[i]];
            verify(node, "app-view route '" + ids[i] + "' has no node in default-menu.jsonc");
            compare(node.kind, "provider");
        }
    }

    // And the view file each one names actually exists, at the path
    // Menu.qml resolves it from (relative to Surfaces/Menu/).
    function test_every_registered_view_file_exists() {
        var ids = Object.keys(AppViews.VIEWS);
        for (var i = 0; i < ids.length; i++) {
            var text = _read("../shell/Surfaces/Menu/" + AppViews.viewFor(ids[i]));
            verify(text.length > 0, "app-view file for '" + ids[i] + "' is missing or empty");
        }
    }
}
