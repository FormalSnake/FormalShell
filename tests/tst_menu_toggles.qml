import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/toggles.js" as Toggles

// Covers shell/Menu/toggles.js plus two drift guards that read shipped files
// rather than fixtures: the "@state:" allow-list only means anything if
// Menu.qml's snapshot literal spells the same four paths and the shipped
// toggle subtree names paths that exist. Reading a file outside the test's
// own directory needs QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner
// invocations in justfile and flake.nix's qml-tests derivation.
TestCase {
    name: "MenuToggles"

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

    function test_prefix_detection() {
        verify(Toggles.isStateCondition("@state:nightlight.active"));
        verify(!Toggles.isStateCondition("command -v wlsunset >/dev/null 2>&1"));
        // `checked` comes from user jsonc, so a non-string must not throw.
        verify(!Toggles.isStateCondition(undefined));
        verify(!Toggles.isStateCondition(null));
        verify(!Toggles.isStateCondition(true));
        compare(Toggles.statePath("@state:nightlight.active"), "nightlight.active");
        verify(Toggles.statePath("command -v wlsunset >/dev/null 2>&1") === null);
        verify(Toggles.statePath(undefined) === null);
    }

    // Membership check, never an object lookup: a hostile menu.jsonc cannot
    // reach the QML engine or a prototype member through this field.
    function test_allow_list_rejects_unknown_and_prototype_paths() {
        compare(Toggles.resolveState("@state:Qt.quit", {}), false);
        compare(Toggles.resolveState("@state:constructor", {}), false);
        compare(Toggles.resolveState("@state:__proto__", {}), false);
        compare(Toggles.resolveState("@state:hasOwnProperty", {}), false);
        compare(Toggles.resolveState("@state:", {}), false);
    }

    function test_resolve_reads_the_snapshot() {
        compare(Toggles.resolveState("@state:notifications.dnd", { "notifications.dnd": true }), true);
        compare(Toggles.resolveState("@state:notifications.dnd", { "notifications.dnd": false }), false);
        // An unpopulated snapshot renders "off", never "unknown".
        compare(Toggles.resolveState("@state:notifications.dnd", {}), false);
        compare(Toggles.resolveState("@state:notifications.dnd", null), false);
    }

    // The tri-state that keeps existing shell-command `checked` fields
    // resolving from the caller's own Process cache.
    function test_non_state_condition_is_undefined() {
        verify(Toggles.resolveState("true", {}) === undefined);
        verify(Toggles.resolveState("test -n \"$NIRI_SOCKET\"", {}) === undefined);
    }

    function test_checked_for_prefers_live_state_over_the_cache() {
        var node = { id: "toggles.dnd", checked: "@state:notifications.dnd" };
        compare(Toggles.checkedFor(node, { "notifications.dnd": false }, { "toggles.dnd": true }), false);
        compare(Toggles.checkedFor(node, { "notifications.dnd": true }, { "toggles.dnd": false }), true);
    }

    function test_checked_for_falls_back_to_the_shell_cache() {
        var node = { id: "x", checked: "test -f /nope" };
        compare(Toggles.checkedFor(node, {}, { "x": true }), true);
        compare(Toggles.checkedFor(node, {}, {}), false);
        compare(Toggles.checkedFor(node, {}, null), false);
    }

    function test_checked_for_without_a_checked_field() {
        compare(Toggles.checkedFor({ id: "y" }, { "theme.dark": true }, { "y": true }), false);
        compare(Toggles.checkedFor(null, null, null), false);
    }

    function test_snapshot_normalizes_to_the_allow_list() {
        var snap = Toggles.snapshot({ "nightlight.active": true, "bogus": true });
        compare(Object.keys(snap).length, Toggles.PATHS.length);
        for (var i = 0; i < Toggles.PATHS.length; i++)
            verify(snap.hasOwnProperty(Toggles.PATHS[i]));
        verify(!snap.hasOwnProperty("bogus"));
        compare(snap["nightlight.active"], true);
        compare(snap["screensaver.stayAwake"], false);
        compare(snap["notifications.dnd"], false);
        compare(snap["theme.dark"], false);
        // Strict === true only, so a truthy non-boolean reads off.
        compare(Toggles.snapshot({ "theme.dark": 1 })["theme.dark"], false);
        compare(Toggles.snapshot(null)["theme.dark"], false);
        var unknown = Toggles.unknownKeys({ "bogus": 1 });
        compare(unknown.length, 1);
        compare(unknown[0], "bogus");
        compare(Toggles.unknownKeys({ "theme.dark": true }).length, 0);
    }

    // The fresh-object contract QML's var change detection depends on.
    function test_with_result_returns_a_fresh_object() {
        var source = { a: true };
        var out = Toggles.withResult(source, "b", false);
        compare(out.a, true);
        compare(out.b, false);
        verify(out !== source);
        compare(Object.keys(source).length, 1);
        verify(source.b === undefined);
    }

    // Breaks loudly if a path is added without updating Menu.qml and the docs.
    function test_allow_list_is_exactly_the_four_documented_paths() {
        compare(Toggles.PATHS.length, 4);
        verify(Toggles.isKnownPath("nightlight.active"));
        verify(Toggles.isKnownPath("screensaver.stayAwake"));
        verify(Toggles.isKnownPath("notifications.dnd"));
        verify(Toggles.isKnownPath("theme.dark"));
        verify(!Toggles.isKnownPath("bluetooth.powered"));
    }

    // Drift guard: a typo in Menu.qml's _stateSnapshot object literal is
    // invisible to qmllint and would render a permanently-off checkmark.
    function test_menu_qml_snapshot_names_every_allow_listed_path() {
        var text = _read("../shell/Surfaces/Menu/Menu.qml");
        verify(text.length > 0);
        for (var i = 0; i < Toggles.PATHS.length; i++)
            verify(text.indexOf("\"" + Toggles.PATHS[i] + "\"") >= 0);
    }

    // Contract test against the real shipped tree, not a fixture: this is
    // what catches a mistyped @state: path or a missing keepOpen in
    // default-menu.jsonc.
    function test_shipped_toggle_subtree_contract() {
        var tree = Model.buildTree(Model.parseJsonc(_read("../shell/Menu/default-menu.jsonc")), {});
        var ids = ["toggles.nightlight", "toggles.stay-awake", "toggles.dnd", "toggles.dark-mode"];
        for (var i = 0; i < ids.length; i++) {
            var node = tree.nodes[ids[i]];
            verify(node);
            compare(node.parentId, "toggles");
            compare(node.kind, "action");
            compare(node.action.indexOf("@ipc:"), 0);
            compare(node.keepOpen, true);
            verify(Toggles.isStateCondition(node.checked));
            verify(Toggles.isKnownPath(Toggles.statePath(node.checked)));
        }
        compare(tree.nodes["toggles"].childIds.length, 4);
        // Dark mode relocated into the hub; the old theme subtree is gone.
        verify(!tree.nodes["theme.mode-toggle"]);
        verify(!tree.nodes["theme"]);
    }
}
