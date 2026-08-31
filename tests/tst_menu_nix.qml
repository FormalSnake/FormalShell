import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers

// The nix runner's pure half (M12 Task 7; M13b Task 4 added the end-state
// machine): trigger parsing, `nix search --json` stdout parsing, the
// exit-code -> outcome mapping, and row building. The debounce/Process
// wiring in Menu.qml is verified by the --menu smoke leg against a
// PATH-shimmed nix (including a gated shim for the in-flight SEARCHING
// state).
TestCase {
    name: "MenuNix"

    // Same shape the smoke rig's shim echoes: two entries, dotted-prefix
    // keys, one version-less field exercised via the empty-string fallback.
    readonly property string canned: JSON.stringify({
        "legacyPackages.x86_64-linux.hello": {
            "description": "A program that produces a familiar, friendly greeting",
            "pname": "hello",
            "version": "2.12.1"
        },
        "legacyPackages.x86_64-linux.python312Packages.requests": {
            "description": "HTTP library",
            "pname": "requests",
            "version": ""
        }
    })

    function test_trigger_query() {
        compare(Providers.nixTriggerQuery(":nix hello"), "hello");
        compare(Providers.nixTriggerQuery(":nix "), "");
        compare(Providers.nixTriggerQuery(":nix"), "");
        verify(Providers.nixTriggerQuery("hello") === null);
        verify(Providers.nixTriggerQuery(":nixos") === null);
        verify(Providers.nixTriggerQuery("") === null);
    }

    function test_parse_strips_prefix_keeps_order() {
        var results = Providers.parseNixSearch(canned);
        compare(results.length, 2);
        compare(results[0].attr, "hello");
        compare(results[0].version, "2.12.1");
        compare(results[0].description, "A program that produces a familiar, friendly greeting");
        // Dotted attrpaths keep everything past the flake/system prefix.
        compare(results[1].attr, "python312Packages.requests");
        compare(results[1].version, "");
    }

    function test_parse_garbage_is_null_empty_is_list() {
        // Unparseable stdout answers null (SEARCH FAILED's input), distinct
        // from nix's clean zero-hit `{}` (NO RESULTS).
        verify(Providers.parseNixSearch("not json") === null);
        verify(Providers.parseNixSearch("") === null);
        verify(Providers.parseNixSearch("null") === null);
        compare(Providers.parseNixSearch("{}").length, 0);
    }

    function test_search_outcome_states() {
        compare(Providers.nixSearchOutcome(127, "").state, "unavailable");
        compare(Providers.nixSearchOutcome(1, canned).state, "failed");
        compare(Providers.nixSearchOutcome(0, "not json").state, "failed");
        compare(Providers.nixSearchOutcome(0, "{}").state, "empty");
        var ok = Providers.nixSearchOutcome(0, canned);
        compare(ok.state, "results");
        compare(ok.results.length, 2);
        compare(ok.results[0].attr, "hello");
        // Failure states never leak partial results.
        compare(Providers.nixSearchOutcome(1, canned).results.length, 0);
    }

    function test_rows_shape() {
        var rows = Providers.nixRows(Providers.parseNixSearch(canned));
        compare(rows.length, 2);
        compare(rows[0].label, "hello 2.12.1");
        compare(rows[0].desc, "A program that produces a familiar, friendly greeting");
        compare(rows[0].kind, "action");
        compare(rows[0].action, "@ipc:nix.run:hello");
        // Launch acknowledgment fields (M13b Task 4): Menu.qml's activation
        // fires notify(notifySummary, notifyBody) alongside the spawn.
        compare(rows[0].notifySummary, "NIX RUN");
        compare(rows[0].notifyBody, "hello");
        // No version: the label is the bare attr.
        compare(rows[1].label, "python312Packages.requests");
        compare(rows[1].notifyBody, "python312Packages.requests");
    }

    function test_rows_skip_unsafe_attrs_and_cap() {
        var unsafe = Providers.nixRows([{ attr: "bad'attr", version: "1", description: "" }]);
        compare(unsafe.length, 0);
        var many = [];
        for (var i = 0; i < 40; i++)
            many.push({ attr: "pkg" + i, version: "1", description: "" });
        compare(Providers.nixRows(many).length, 30);
    }

    function test_note_rows() {
        var cases = [
            [Providers.nixUnavailableRow(), "nix.unavailable", "NO NIX"],
            [Providers.nixIndexingRow(), "nix.indexing", "INDEXING NIXPKGS"],
            [Providers.nixSearchingRow(), "nix.searching", "SEARCHING"],
            [Providers.nixNoResultsRow(), "nix.noresults", "NO RESULTS"],
            [Providers.nixFailedRow(), "nix.failed", "SEARCH FAILED"]
        ];
        for (var i = 0; i < cases.length; i++) {
            compare(cases[i][0].id, cases[i][1]);
            compare(cases[i][0].label, cases[i][2]);
            // kind "note" matches no _activateRow branch: not activatable.
            compare(cases[i][0].kind, "note");
            compare(cases[i][0].dim, true);
        }
    }
}
