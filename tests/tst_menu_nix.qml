import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers

// The nix runner's pure half (M12 Task 7): trigger parsing, `nix search
// --json` stdout parsing, and row building. The debounce/Process wiring in
// Menu.qml is verified by the --menu smoke leg against a PATH-shimmed nix.
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

    function test_parse_garbage_is_empty() {
        compare(Providers.parseNixSearch("not json").length, 0);
        compare(Providers.parseNixSearch("").length, 0);
        compare(Providers.parseNixSearch("null").length, 0);
        compare(Providers.parseNixSearch("{}").length, 0);
    }

    function test_rows_shape() {
        var rows = Providers.nixRows(Providers.parseNixSearch(canned));
        compare(rows.length, 2);
        compare(rows[0].label, "hello 2.12.1");
        compare(rows[0].desc, "A program that produces a familiar, friendly greeting");
        compare(rows[0].kind, "action");
        compare(rows[0].action, "ghostty -e sh -c 'nix run nixpkgs#hello; read'");
        // No version: the label is the bare attr.
        compare(rows[1].label, "python312Packages.requests");
    }

    function test_rows_skip_unsafe_attrs_and_cap() {
        var unsafe = Providers.nixRows([{ attr: "bad'attr", version: "1", description: "" }]);
        compare(unsafe.length, 0);
        var many = [];
        for (var i = 0; i < 40; i++)
            many.push({ attr: "pkg" + i, version: "1", description: "" });
        compare(Providers.nixRows(many).length, 30);
    }

    function test_unavailable_row() {
        var row = Providers.nixUnavailableRow();
        compare(row.label, "NO NIX");
        compare(row.kind, "note");
        compare(row.dim, true);
    }
}
