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
        ]);
        compare(nodes.length, 1);
        compare(nodes[0].id, "clipboard.a");
        compare(nodes[0].label, "hello world");
        compare(nodes[0].kind, "action");
        compare(nodes[0].desc, "");
        compare(nodes[0].thumbSource, "");
        compare(nodes[0].fullText, "hello world");
        compare(nodes[0].time, "14:02");
        // In-process, not a spawned `qs ipc` command: `qs` is quickshell's
        // own binary and nothing puts it on a session PATH, so the spawned
        // form was a silent exit 127 everywhere but the smoke VM.
        compare(nodes[0].action, "@ipc:clipboard.copy:a");
        compare(nodes[0].pasteAfter, true);
        compare(nodes[0].verb, "Paste");
    }

    // Shift+Enter's target (M50), on image rows in copy mode alone: a text
    // row has no file to send, and a share row's Shift+Enter has nothing of
    // its own to do.
    function test_clipssh_path_rides_copy_mode_image_rows_only() {
        var entries = [
            { id: "img", kind: "image", path: "/state/clipboard-images/abc.png", capturedAt: 0 },
            { id: "txt", kind: "text", text: "hello", capturedAt: 0 }
        ];
        var copyRows = Providers.clipboardProvider(entries, "copy");
        compare(copyRows[0].clipsshPath, "/state/clipboard-images/abc.png");
        compare(copyRows[1].clipsshPath, "");
        var shareRows = Providers.clipboardProvider(entries, "share");
        compare(shareRows[0].clipsshPath, "");
        compare(shareRows[1].clipsshPath, "");
    }

    function test_legacy_text_entry_without_kind_still_maps_as_text() {
        // Entries persisted before history.js learned `kind` have none —
        // the provider must not mistake that for an image row.
        var nodes = Providers.clipboardProvider([{ id: "a", text: "legacy" }]);
        compare(nodes[0].label, "legacy");
        compare(nodes[0].thumbSource, "");
    }

    function test_image_entry_maps_to_image_label_desc_and_thumb() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/state/clipboard-images/abc.png", mime: "image/png", capturedAt: new Date(2026, 0, 1, 9, 5).getTime() }
        ]);
        compare(nodes.length, 1);
        compare(nodes[0].id, "clipboard.b");
        compare(nodes[0].label, "IMAGE");
        compare(nodes[0].desc, "09:05");
        compare(nodes[0].thumbSource, "/state/clipboard-images/abc.png");
        compare(nodes[0].fullText, "");
        compare(nodes[0].time, "09:05");
        compare(nodes[0].action, "@ipc:clipboard.copy:b");
        compare(nodes[0].pasteAfter, true);
    }

    function test_mixed_entries_preserve_order() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/img/one.png", capturedAt: 1000 },
            { id: "a", kind: "text", text: "one", capturedAt: 999 }
        ]);
        compare(nodes.length, 2);
        compare(nodes[0].label, "IMAGE");
        compare(nodes[1].label, "one");
    }

    function test_empty_items_maps_to_empty_list() {
        compare(Providers.clipboardProvider([]).length, 0);
        compare(Providers.clipboardProvider(undefined).length, 0);
    }

    // clipboard.paste off: the row still copies, it just stops touching the
    // focused window, and says Copy rather than promising a paste.
    function test_paste_disabled_drops_paste_marker_and_changes_verb() {
        var nodes = Providers.clipboardProvider([{ id: "a", text: "hi" }], "copy", false);
        compare(nodes[0].action, "@ipc:clipboard.copy:a");
        compare(nodes[0].pasteAfter, false);
        compare(nodes[0].verb, "Copy");
    }

    // Share rows hand the entry to LocalSend and never synthesize input,
    // whatever clipboard.paste says.
    function test_share_rows_never_paste() {
        var nodes = Providers.clipboardProvider([{ id: "a", text: "hi" }], "share", true);
        compare(nodes[0].id, "share.history.a");
        compare(nodes[0].pasteAfter, false);
        compare(nodes[0].verb, "Share");
        verify(nodes[0].action.indexOf("@ipc:") < 0);
    }

    // pasteArgv: wtype's press/tap/release argv for a chord, releases in
    // reverse order so the modifiers unwind the way they were pressed.
    function test_paste_argv_default_chord() {
        compare(Providers.pasteArgv("ctrl+v"), ["-M", "ctrl", "-k", "v", "-m", "ctrl"]);
    }

    function test_paste_argv_multiple_modifiers_release_in_reverse() {
        compare(Providers.pasteArgv("ctrl+shift+v"),
                ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"]);
    }

    function test_paste_argv_is_case_and_space_insensitive() {
        compare(Providers.pasteArgv(" Ctrl + V "), ["-M", "ctrl", "-k", "v", "-m", "ctrl"]);
    }

    function test_paste_argv_bare_key_needs_no_modifier() {
        compare(Providers.pasteArgv("insert"), ["-k", "insert"]);
    }

    // A typo pastes nothing rather than some other keystroke. "super" is in
    // here deliberately: it reads like a modifier wtype would take and is
    // not one (probed against the binary — the windows key is "logo").
    function test_paste_argv_rejects_unknown_modifier() {
        compare(Providers.pasteArgv("cmd+v"), null);
        compare(Providers.pasteArgv("super+v"), null);
        compare(Providers.pasteArgv("meta+v"), null);
    }

    function test_paste_argv_accepts_the_windows_key_as_logo() {
        compare(Providers.pasteArgv("logo+v"), ["-M", "logo", "-k", "v", "-m", "logo"]);
    }

    function test_paste_argv_rejects_a_chord_with_no_key() {
        compare(Providers.pasteArgv("ctrl+shift"), null);
        compare(Providers.pasteArgv(""), null);
        compare(Providers.pasteArgv(undefined), null);
    }

    // clipboardSearch: the route-local filter (M30). Pure over already-
    // built rows, so these tests build rows through the real provider
    // rather than hand-rolling node shapes.
    function test_search_empty_query_returns_rows_unchanged() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "hello", capturedAt: 1000 }
        ]);
        compare(Providers.clipboardSearch(rows, ""), rows);
        compare(Providers.clipboardSearch(rows, "   "), rows);
    }

    function test_search_matches_beyond_the_truncated_label() {
        var longText = "x".repeat(80) + "findme";
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: longText, capturedAt: 1000 }
        ]);
        // The label truncates at 60 chars; the match text does not.
        verify(rows[0].label.indexOf("findme") < 0);
        compare(Providers.clipboardSearch(rows, "findme").length, 1);
    }

    function test_search_is_case_insensitive() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "Hello World", capturedAt: 1000 }
        ]);
        compare(Providers.clipboardSearch(rows, "WORLD").length, 1);
        compare(Providers.clipboardSearch(rows, "world").length, 1);
    }

    function test_search_finds_image_rows_by_their_label() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "image", path: "/img/one.png", capturedAt: 1000 },
            { id: "b", kind: "text", text: "grocery list", capturedAt: 999 }
        ]);
        var hits = Providers.clipboardSearch(rows, "image");
        compare(hits.length, 1);
        compare(hits[0].id, "clipboard.a");
    }

    function test_search_excludes_non_matching_rows() {
        var rows = Providers.clipboardProvider([
            { id: "a", kind: "text", text: "apple", capturedAt: 1000 },
            { id: "b", kind: "text", text: "banana", capturedAt: 999 }
        ]);
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
