import QtQuick
import QtTest
import "../shell/Menu/hints.js" as Hints

// The launcher's row hints (M48 D6). The chord half is checked against the
// shipped example config itself rather than against a copy of the same
// strings: hints.js deliberately does not parse that file at runtime (see
// its header), so this is what keeps the table from drifting the first time
// a bind moves. Reading a file outside the test's own directory needs
// QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner invocations in
// justfile and flake.nix's qml-tests derivation.
TestCase {
    name: "MenuHints"

    property string conf: ""

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../docs/examples/hyprland/formalshell.conf"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        conf = xhr.responseText;
    }

    function _titleCase(word) {
        return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    }

    // `bind = SUPER CTRL, E, exec, $fs menu summon emoji` -> emoji:
    // "Super+Ctrl+E". Only the summon binds matter; `menu toggle` reaches no
    // route in particular.
    function _confChords() {
        var out = {};
        var lines = conf.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.indexOf("bind") !== 0)
                continue;
            var eq = line.indexOf("=");
            if (eq < 0)
                continue;
            var fields = line.slice(eq + 1).split(",");
            if (fields.length < 4)
                continue;
            var route = fields.slice(3).join(",").trim().match(/menu summon ([a-z][a-z.]*)$/);
            if (!route)
                continue;
            var mods = fields[0].trim();
            var parts = mods === "" ? [] : mods.split(/\s+/);
            parts.push(fields[1].trim());
            out[route[1]] = parts.map(_titleCase).join("+");
        }
        return out;
    }

    function test_chords_match_the_shipped_config() {
        var confChords = _confChords();
        var routes = Object.keys(confChords);
        verify(routes.length >= 10);
        for (var i = 0; i < routes.length; i++)
            compare(Hints.chordFor(routes[i]), confChords[routes[i]],
                "chord for " + routes[i]);
        var listed = Object.keys(Hints.ROUTE_CHORDS);
        for (var j = 0; j < listed.length; j++)
            verify(confChords[listed[j]] !== undefined,
                listed[j] + " has a chord here but no bind in the example config");
    }

    function test_unbound_route_has_no_chord() {
        compare(Hints.chordFor("panels"), "");
        compare(Hints.chordFor(""), "");
        compare(Hints.chordFor(undefined), "");
    }

    // A count belongs to a listing, not to a handful of named commands.
    function test_count_is_provider_only() {
        compare(Hints.countFor({ id: "tray", kind: "provider", childIds: ["a", "b"] }), "2");
        compare(Hints.countFor({ id: "tray", kind: "provider", childIds: [] }), "");
        compare(Hints.countFor({ id: "reminder", kind: "submenu", childIds: ["a", "b", "c"] }), "");
        compare(Hints.countFor({ id: "apps.firefox", kind: "app", childIds: [] }), "");
    }

    function test_chord_wins_over_count() {
        compare(Hints.hintFor({ id: "apps", kind: "provider", childIds: ["a", "b"] }), "Super+Alt+Space");
        compare(Hints.hintFor({ id: "panels", kind: "provider", childIds: ["a", "b"] }), "2");
        compare(Hints.hintFor({ id: "apps.firefox", kind: "app", childIds: [] }), "");
        compare(Hints.hintFor(null), "");
    }
}
