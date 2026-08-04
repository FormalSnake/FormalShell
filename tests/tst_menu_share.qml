import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The SHARE route's pure logic (M17 Task 1, LocalSend integration):
// shareEntryCommand's text/image split, shareClipboardEntry's dynamic root
// injection (wallpaperEntry()'s own pattern) including its honest empty
// state, and clipboardProvider's "share" mode reusing today's "copy" rows
// byte-identical. Menu.qml's tree wiring/activation is out of scope — same
// split as tst_menu_clipboard.qml/tst_menu_wallpaper.qml.
TestCase {
    name: "MenuShare"

    function test_text_entry_uses_the_localsend_text_flag() {
        var cmd = Providers.shareEntryCommand({ id: "a", text: "hello world" });
        compare(cmd, "localsend_app -t 'hello world'");
    }

    function test_text_entry_escapes_embedded_single_quotes() {
        var cmd = Providers.shareEntryCommand({ id: "a", text: "it's here" });
        compare(cmd, "localsend_app -t 'it'\\''s here'");
    }

    function test_image_entry_shares_its_content_addressed_path_directly() {
        var cmd = Providers.shareEntryCommand({ id: "b", kind: "image", path: "/state/clipboard-images/abc.png" });
        compare(cmd, "localsend_app '/state/clipboard-images/abc.png'");
    }

    function test_empty_history_maps_to_a_dim_note_row() {
        var entry = Providers.shareClipboardEntry([]);
        var node = entry["share.clipboard"];
        verify(node);
        compare(node.label, "Nothing To Share");
        compare(node.kind, "note");
        compare(node.dim, true);
        verify(node.action === undefined);
    }

    function test_undefined_history_maps_to_a_dim_note_row_too() {
        var entry = Providers.shareClipboardEntry(undefined);
        compare(entry["share.clipboard"].kind, "note");
    }

    function test_newest_entry_maps_to_a_share_action() {
        var entry = Providers.shareClipboardEntry([
            { id: "a", text: "newest" },
            { id: "b", text: "older" }
        ]);
        var node = entry["share.clipboard"];
        compare(node.label, "Clipboard");
        compare(node.action, "localsend_app -t 'newest'");
    }

    // Mirrors tst_menu_wallpaper.qml's merge test: default-menu.jsonc
    // declares a "share.clipboard" placeholder so the dynamic fragment's
    // key overwrites rather than appends — the row keeps its declared
    // position (JS object key order tracks first insertion, not last
    // write) instead of jumping to the end of the level.
    function test_merged_entry_preserves_declared_position_and_builds_action_node() {
        var def = {
            "share": { label: "Share" },
            "share.clipboard": { label: "Clipboard" },
            "share.history": { label: "Pick From History", provider: "shareHistory" },
            "share.receive": { label: "Receive", action: "localsend_app" }
        };
        var dynamic = Providers.shareClipboardEntry([{ id: "a", text: "hi" }]);
        Object.keys(dynamic).forEach(function (k) { def[k] = dynamic[k]; });
        var tree = Model.buildTree(def, {});
        var share = tree.nodes["share"];
        compare(share.childIds.length, 3);
        compare(share.childIds[0], "share.clipboard");
        compare(share.childIds[1], "share.history");
        compare(share.childIds[2], "share.receive");
        compare(tree.nodes["share.clipboard"].kind, "action");
    }

    function test_share_mode_reuses_copy_rows_with_a_distinct_id_namespace() {
        var nodes = Providers.clipboardProvider([
            { id: "a", text: "hello" }
        ], "/store/share/formalshell", "share");
        compare(nodes.length, 1);
        compare(nodes[0].id, "share.history.a");
        compare(nodes[0].label, "hello");
        compare(nodes[0].kind, "action");
        compare(nodes[0].action, "localsend_app -t 'hello'");
    }

    function test_share_mode_preserves_image_rows_shape() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/img/one.png", capturedAt: new Date(2026, 0, 1, 9, 5).getTime() }
        ], "/self", "share");
        compare(nodes[0].id, "share.history.b");
        compare(nodes[0].label, "IMAGE");
        compare(nodes[0].desc, "09:05");
        compare(nodes[0].thumbSource, "/img/one.png");
        compare(nodes[0].action, "localsend_app '/img/one.png'");
    }

    function test_default_copy_mode_is_unaffected_by_the_new_parameter() {
        var nodes = Providers.clipboardProvider([{ id: "a", text: "hello" }], "/store/share/formalshell");
        compare(nodes[0].id, "clipboard.a");
        compare(nodes[0].action, "qs ipc --any-display -p /store/share/formalshell call clipboard copy a");
    }

    // The presence-gate itself (default-menu.jsonc's "share" node): the
    // same `when` mechanism system.logout's NIRI_SOCKET guard already
    // proves in tst_menu_model.qml's self-pruning-cascade test, exercised
    // here with the localsend command string. visibleChildren() only ever
    // sees a resolved condResults entry (Menu.qml's own _runCondition
    // fills that in from a real `sh -c` exit code) — this proves the tree
    // wiring honors both outcomes, not the `command -v` shell behavior
    // itself, which is standard POSIX and not FormalShell's to re-verify.
    function test_share_node_when_gate_hides_and_shows_the_whole_subtree() {
        var def = {
            "share": { label: "Share", when: "command -v localsend_app >/dev/null 2>&1" },
            "share.receive": { label: "Receive", action: "localsend_app" }
        };
        var tree = Model.buildTree(def, {});
        compare(Model.visibleChildren(tree.nodes, null, { "share": false }).length, 0);
        var visible = Model.visibleChildren(tree.nodes, null, { "share": true });
        compare(visible.length, 1);
        compare(visible[0].id, "share");
    }
}
