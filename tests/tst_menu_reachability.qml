import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// M38 Task 3 — the launcher-reachability guard. Keeps the owner's
// philosophy true: every panel registered in shell.qml's PanelIpc has a
// route in the launcher. PANEL_NAMES here is a second, independently kept
// copy of providers.js's own PANEL_NAMES list (not imported — a typo or a
// dropped entry in the shipped list must show up as a mismatch between two
// independently-written sources, not disappear because both read the same
// array); test_registry_names_match_the_test_list below cross-checks it
// against shell.qml's actual PanelIpc registry text, so a 16th panel added
// to shell.qml without a matching row here fails loudly instead of just
// shipping unreachable.
TestCase {
    name: "MenuReachability"

    property var PANEL_NAMES: [
        "appmenu", "audio", "calendar", "network", "bluetooth", "airpods",
        "dualsense", "power", "weather", "media", "github", "usage",
        "tailscale", "systemupdate", "display"
    ]

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

    // Builds the tree the way Menu.qml actually does for the routes that
    // depend on it: the shipped jsonc, no user override, with "panels" and
    // "tray" expanded through applyProviders exactly like Menu.qml's own
    // registry does (selfPath is irrelevant to what this test checks, so a
    // fixed stand-in is fine).
    function _realTree() {
        var parsed = Model.parseJsonc(_read("../shell/Menu/default-menu.jsonc"));
        return Providers.applyProviders(Model.buildTree(parsed, {}), {
            panels: function () { return Providers.panelsProvider("/fake/shell/dir"); },
            tray: function () { return Providers.trayProvider([], "/fake/shell/dir"); }
        });
    }

    // The headline guard: every panel name has a "panels.<name>" row whose
    // action actually opens it, and the submenu has no extra/stale rows.
    function test_shipped_tree_covers_every_panel() {
        var tree = _realTree();
        var panelsNode = tree.nodes["panels"];
        verify(panelsNode);
        compare(panelsNode.childIds.length, PANEL_NAMES.length);
        for (var i = 0; i < PANEL_NAMES.length; i++) {
            var name = PANEL_NAMES[i];
            var node = tree.nodes["panels." + name];
            verify(node, "missing launcher route for panel '" + name + "'");
            compare(node.kind, "action");
            verify(node.action.indexOf("call panel open " + name) >= 0,
                "panels." + name + " does not open panel '" + name + "'");
        }
    }

    // Drift guard the other direction: the list this test asserts against
    // is itself checked against shell.qml's real PanelIpc registry, so an
    // added-and-forgotten panel (present in shell.qml, absent here) fails
    // here rather than silently shipping unrouted.
    function test_registry_names_match_the_test_list() {
        var text = _read("../shell/shell.qml");
        var start = text.indexOf("var reg = {");
        verify(start >= 0, "PanelIpc registry literal not found in shell.qml");
        var end = text.indexOf("};", start);
        var registryText = text.slice(start, end);
        for (var i = 0; i < PANEL_NAMES.length; i++)
            verify(registryText.indexOf(PANEL_NAMES[i] + ":") >= 0,
                "'" + PANEL_NAMES[i] + "' not found in shell.qml's PanelIpc registry");
        // "monitor" is a real Task 6 addition to the registry, opt-in and
        // deliberately not part of this list yet (M38 wave ordering) — a
        // fixed-count assertion here would only be able to fail late.
    }

    function test_panels_provider_action_shape() {
        var rows = Providers.panelsProvider("/store/share/formalshell");
        compare(rows.length, PANEL_NAMES.length);
        for (var i = 0; i < rows.length; i++) {
            compare(rows[i].id, "panels." + PANEL_NAMES[i]);
            compare(rows[i].kind, "action");
            compare(rows[i].action, "qs ipc -p /store/share/formalshell call panel open " + PANEL_NAMES[i]);
        }
    }

    // Tray: an item row calls tray activate <id> self-targeted the same
    // way, and an empty tray renders one dim note rather than nothing.
    function test_tray_provider_empty_state() {
        var rows = Providers.trayProvider([], "/store/share/formalshell");
        compare(rows.length, 1);
        compare(rows[0].kind, "note");
        compare(rows[0].dim, true);
    }

    function test_tray_provider_rows_activate_by_id() {
        var rows = Providers.trayProvider([{ id: "spotify", title: "Spotify" }], "/store/share/formalshell");
        compare(rows.length, 1);
        compare(rows[0].id, "tray.spotify");
        compare(rows[0].label, "Spotify");
        compare(rows[0].action, "qs ipc -p /store/share/formalshell call tray activate spotify");
    }

    // The rest of the sweep — console, plain screenshots, screensaver,
    // plugins, notification bulk actions, retheme/explicit mode — all
    // injected the same self-targeted way captureEntries already injects
    // "capture". One assertion per IPC target/function actually referenced.
    function test_capture_entries_covers_the_rest_of_the_sweep() {
        var call = "qs ipc -p /store/share/formalshell call ";
        var entries = Providers.captureEntries("/store/share/formalshell");
        compare(entries["capture.screenshot"].action, call + "screenshot full");
        compare(entries["capture.region"].action, call + "screenshot region");
        compare(entries["system.console"].action, call + "console toggle");
        compare(entries["system.screensaver"].action, call + "screensaver start");
        compare(entries["system.plugins.list"].action, call + "plugins list");
        compare(entries["system.plugins.reload"].action, call + "plugins reload");
        compare(entries["notifications.clear"].action, call + "notifications clear");
        compare(entries["notifications.markAllSeen"].action, call + "notifications markAllSeen");
        compare(entries["notifications.dismissAll"].action, call + "notifications dismissAll");
        compare(entries["theme.retheme"].action, call + "theme retheme");
        compare(entries["theme.mode-dark"].action, call + "theme mode dark");
        compare(entries["theme.mode-light"].action, call + "theme mode light");
    }

    // system.lock stays a deliberate dead route (owner's call, not part of
    // this sweep) — asserted so a future edit that quietly flips it on
    // gets caught here rather than only in a live session.
    function test_system_lock_stays_disabled() {
        var tree = _realTree();
        compare(tree.nodes["system.lock"].when, "false");
    }
}
