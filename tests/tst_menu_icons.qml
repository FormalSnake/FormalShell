import QtQuick
import QtTest
import "../shell/Menu/icons.js" as MenuIcons
import "../shell/Menu/model.js" as Model
import "../shell/Theme/icons.js" as Icons

// M43 D2: shell/Menu/icons.js maps the shipped route ids onto icon names so
// MenuRow can draw them through `Icon`. Two drift guards read shipped files
// rather than fixtures: a name that does not resolve in a set renders as
// circle-help, and a route added to default-menu.jsonc without a mapping
// renders with no icon at all.
// Reading a file outside the test's own directory needs
// QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner invocations in
// justfile and flake.nix's qml-tests derivation.
TestCase {
    name: "MenuIcons"

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

    function test_every_mapped_name_resolves_in_both_sets() {
        var sets = ["lucide", "nerd"];
        var ids = Object.keys(MenuIcons.ROUTE_ICONS);
        verify(ids.length > 0);
        for (var s = 0; s < sets.length; s++) {
            var fallback = Icons.glyph(sets[s], "circle-help");
            for (var i = 0; i < ids.length; i++) {
                var name = MenuIcons.ROUTE_ICONS[ids[i]];
                verify(Icons.glyph(sets[s], name) !== fallback,
                    ids[i] + " -> " + name + " fell back in " + sets[s]);
            }
        }
    }

    // The point of the map: every route the shell ships names its icon here.
    // A route added without one still renders, just bare, so only this test
    // catches the omission.
    function test_every_shipped_route_is_mapped() {
        var tree = Model.buildTree(Model.parseJsonc(_read("../shell/Menu/default-menu.jsonc")), {});
        var ids = Object.keys(tree.nodes);
        verify(ids.length > 0);
        var mapped = 0;
        for (var i = 0; i < ids.length; i++) {
            var node = tree.nodes[ids[i]];
            if (!node.id || node.id === "")
                continue;
            verify(MenuIcons.iconFor(node) !== "", node.id + " has no mapped icon name");
            mapped++;
        }
        verify(mapped > 0);
    }

    function test_an_unmapped_row_keeps_its_own_glyph() {
        // An emoji row's icon IS the emoji, and a user menu.jsonc route
        // names an id this map has never heard of.
        compare(MenuIcons.iconFor({ id: "emoji.a", icon: "a" }), "");
        compare(MenuIcons.iconFor({ id: "my.own.route" }), "");
        compare(MenuIcons.iconFor({}), "");
        compare(MenuIcons.iconFor(null), "");
        compare(MenuIcons.iconFor(undefined), "");
    }

    function test_a_mapped_row_answers_with_its_name() {
        compare(MenuIcons.iconFor({ id: "clipboard" }), "clipboard");
        compare(MenuIcons.iconFor({ id: "toggles.dnd" }), "bell-off");
        compare(MenuIcons.iconFor({ id: "panels.network" }), "wifi");
    }
}
