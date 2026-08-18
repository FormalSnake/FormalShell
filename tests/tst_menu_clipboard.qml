import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers

// clipboardProvider's node shape (M14 Task 1): text rows get a truncated
// preview label; image rows (history.js's `kind: "image"`) get a fixed
// IMAGE label, a capture-time desc, and a thumbSource for Task 6's
// thumbnail row. Menu.qml's activation/debounce wiring is out of scope —
// this is the pure half, same split as tst_menu_nix.qml/tst_menu_apps.qml.
TestCase {
    name: "MenuClipboard"

    function test_text_entry_maps_to_preview_label_action_node() {
        var nodes = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "hello world", capturedAt: new Date(2026, 0, 1, 14, 2).getTime() }
        ], "/store/share/formalshell");
        compare(nodes.length, 1);
        compare(nodes[0].id, "clipboard.a");
        compare(nodes[0].label, "hello world");
        compare(nodes[0].kind, "action");
        compare(nodes[0].desc, "");
        compare(nodes[0].thumbSource, "");
        compare(nodes[0].fullText, "hello world");
        compare(nodes[0].time, "14:02");
        compare(nodes[0].action, "qs ipc -p /store/share/formalshell call clipboard copy a");
    }

    function test_legacy_text_entry_without_kind_still_maps_as_text() {
        // Entries persisted before history.js learned `kind` have none —
        // the provider must not mistake that for an image row.
        var nodes = Providers.clipboardProvider([{ id: "a", text: "legacy" }], "/self");
        compare(nodes[0].label, "legacy");
        compare(nodes[0].thumbSource, "");
    }

    function test_image_entry_maps_to_image_label_desc_and_thumb() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/state/clipboard-images/abc.png", mime: "image/png", capturedAt: new Date(2026, 0, 1, 9, 5).getTime() }
        ], "/store/share/formalshell");
        compare(nodes.length, 1);
        compare(nodes[0].id, "clipboard.b");
        compare(nodes[0].label, "IMAGE");
        compare(nodes[0].desc, "09:05");
        compare(nodes[0].thumbSource, "/state/clipboard-images/abc.png");
        compare(nodes[0].fullText, "");
        compare(nodes[0].time, "09:05");
        compare(nodes[0].action, "qs ipc -p /store/share/formalshell call clipboard copy b");
    }

    function test_mixed_entries_preserve_order() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/img/one.png", capturedAt: 1000 },
            { id: "a", kind: "text", text: "one", capturedAt: 999 }
        ], "/self");
        compare(nodes.length, 2);
        compare(nodes[0].label, "IMAGE");
        compare(nodes[1].label, "one");
    }

    function test_empty_items_maps_to_empty_list() {
        compare(Providers.clipboardProvider([], "/self").length, 0);
        compare(Providers.clipboardProvider(undefined, "/self").length, 0);
    }

    // clipboardSearch: the route-local filter (M30). Pure over already-
    // built rows, so these tests build rows through the real provider
    // rather than hand-rolling node shapes.
    function test_search_empty_query_returns_rows_unchanged() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "hello", capturedAt: 1000 }
        ], "/self");
        compare(Providers.clipboardSearch(rows, ""), rows);
        compare(Providers.clipboardSearch(rows, "   "), rows);
    }

    function test_search_matches_beyond_the_truncated_label() {
        var longText = "x".repeat(80) + "findme";
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: longText, capturedAt: 1000 }
        ], "/self");
        // The label truncates at 60 chars; the match text does not.
        verify(rows[0].label.indexOf("findme") < 0);
        compare(Providers.clipboardSearch(rows, "findme").length, 1);
    }

    function test_search_is_case_insensitive() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "Hello World", capturedAt: 1000 }
        ], "/self");
        compare(Providers.clipboardSearch(rows, "WORLD").length, 1);
        compare(Providers.clipboardSearch(rows, "world").length, 1);
    }

    function test_search_finds_image_rows_by_their_label() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "image", path: "/img/one.png", capturedAt: 1000 },
            { id: "b", kind: "text", text: "grocery list", capturedAt: 999 }
        ], "/self");
        var hits = Providers.clipboardSearch(rows, "image");
        compare(hits.length, 1);
        compare(hits[0].id, "clipboard.a");
    }

    function test_search_excludes_non_matching_rows() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "apple", capturedAt: 1000 },
            { id: "b", kind: "text", text: "banana", capturedAt: 999 }
        ], "/self");
        var hits = Providers.clipboardSearch(rows, "apple");
        compare(hits.length, 1);
        compare(hits[0].id, "clipboard.a");
    }

    // Honest empty-list notes (M30): dim, non-activatable, no colon.
    function test_empty_row_shape() {
        var row = Providers.clipboardEmptyRow();
        compare(row.label, "CLIPBOARD EMPTY");
        compare(row.kind, "note");
        compare(row.dim, true);
    }

    function test_no_match_row_shape() {
        var row = Providers.clipboardNoMatchRow();
        compare(row.label, "NO MATCHES");
        compare(row.kind, "note");
        compare(row.dim, true);
    }
}
