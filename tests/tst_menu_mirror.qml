import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers
import "../shell/Menu/search.js" as Search

// The camera mirror owns the word "mirror" in the launcher; the display
// panel's output mirroring stays reachable under its own words.
TestCase {
    name: "MenuMirror"

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

    function _tree() {
        var parsed = Model.parseJsonc(_read("../shell/Menu/default-menu.jsonc"));
        return Providers.applyProviders(Model.buildTree(parsed, {}), {
            panels: function () { return Providers.panelsProvider("/fake/shell/dir"); },
            tray: function () { return Providers.trayProvider([], "/fake/shell/dir"); }
        });
    }

    function _first(query, within) {
        var ranked = Search.rank(_tree().nodes, query, {}, within);
        return ranked.length > 0 ? ranked[0].id : "";
    }

    function test_mirror_reaches_the_camera_route_first() {
        compare(_first("mirror"), "mirror");
    }

    function test_camera_and_webcam_reach_the_camera_route() {
        compare(_first("webcam"), "mirror");
        compare(_first("camera"), "mirror");
    }

    // The panels submenu is route-only: its rows are searched from inside
    // it, where the Display panel's mirroring words find it.
    function test_display_mirroring_stays_reachable() {
        compare(_first("mirror display", "panels"), "panels.display");
        compare(_first("screen mirroring", "panels"), "panels.display");
    }
}
