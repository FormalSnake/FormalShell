import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// The SHARE route's pure logic (M17 Task 1, restructured for localsend-cli
// by M75 Task 5): shareEntryCommand's text/image split (the GUI fallback's
// launch command), sharePeerEntries' dynamic subtree in both its shapes
// (localsend-cli present: peers under Send, a Receive status line; absent:
// the M17 GUI shape unchanged), and clipboardProvider's "share" mode
// reusing today's "copy" rows byte-identical. Menu.qml's tree wiring and
// activation are out of scope, the same split as
// tst_menu_clipboard.qml/tst_menu_wallpaper.qml.
TestCase {
    name: "MenuShare"

    function test_text_entry_writes_a_mktemp_file_and_shares_its_path() {
        var cmd = Providers.shareEntryCommand({ id: "a", text: "hello world" });
        compare(cmd, "tmp=$(mktemp --suffix=.txt) && printf '%s' 'hello world' > \"$tmp\" && exec localsend_app \"$tmp\"");
    }

    function test_text_entry_escapes_embedded_single_quotes() {
        var cmd = Providers.shareEntryCommand({ id: "a", text: "it's here" });
        compare(cmd, "tmp=$(mktemp --suffix=.txt) && printf '%s' 'it'\\''s here' > \"$tmp\" && exec localsend_app \"$tmp\"");
    }

    function test_image_entry_shares_its_content_addressed_path_directly() {
        var cmd = Providers.shareEntryCommand({ id: "b", kind: "image", path: "/state/clipboard-images/abc.png" });
        compare(cmd, "localsend_app '/state/clipboard-images/abc.png'");
    }

    // --- fallback shape (installed=false, the M17 GUI path) ----------------

    function test_fallback_empty_clipboard_maps_share_send_to_a_dim_note_row() {
        var out = Providers.sharePeerEntries(false, [], [], null);
        var node = out["share.send"];
        verify(node);
        compare(node.label, "Nothing to share");
        compare(node.kind, "note");
        compare(node.dim, true);
        verify(node.action === undefined);
    }

    function test_fallback_newest_entry_maps_share_send_to_a_launch_action() {
        var out = Providers.sharePeerEntries(false, [], [
            { id: "a", text: "newest" },
            { id: "b", text: "older" }
        ], null);
        compare(out["share.send"].label, "Send");
        compare(out["share.send"].action, "tmp=$(mktemp --suffix=.txt) && printf '%s' 'newest' > \"$tmp\" && exec localsend_app \"$tmp\"");
    }

    function test_fallback_receive_launches_the_gui_and_history_stays_a_provider_node() {
        var out = Providers.sharePeerEntries(false, [], [], null);
        compare(out["share.receive"].action, "localsend_app");
        compare(out["share.history"].provider, "shareHistory");
    }

    // --- CLI shape (installed=true) -----------------------------------------

    function test_installed_no_peers_is_an_honest_empty_send() {
        var out = Providers.sharePeerEntries(true, [], [], null);
        compare(out["share.send"].label, "Send");
        var empty = out["share.send.empty"];
        verify(empty);
        compare(empty.kind, "note");
        compare(empty.dim, true);
        verify(out["share.send.0"] === undefined);
    }

    function test_installed_peer_gets_a_folder_with_clipboard_and_image_rows() {
        var peers = [{ name: "Kyan's iPhone", ip: "192.168.1.42", port: 53317, protocol: "https" }];
        var items = [
            { id: "t1", kind: "text", text: "hi" },
            { id: "i1", kind: "image", path: "/img/one.png", capturedAt: new Date(2026, 0, 1, 9, 5).getTime() }
        ];
        var out = Providers.sharePeerEntries(true, peers, items, null);
        var folder = out["share.send.0"];
        verify(folder);
        compare(folder.label, "Kyan's iPhone");
        verify(folder.action === undefined); // a folder, not itself activatable

        var clip = out["share.send.0.clipboard"];
        compare(clip.label, "Clipboard");
        compare(clip.action, "@ipc:localsend.send:0:t1");

        var img = out["share.send.0.image.0"];
        compare(img.label, "Image");
        compare(img.desc, "09:05");
        compare(img.thumbSource, "/img/one.png");
        compare(img.action, "@ipc:localsend.send:0:i1");
    }

    function test_installed_peer_with_only_images_gets_no_clipboard_row() {
        var peers = [{ name: "Desk", ip: "10.0.0.5", port: 53317, protocol: "https" }];
        var items = [{ id: "i1", kind: "image", path: "/img/one.png", capturedAt: 0 }];
        var out = Providers.sharePeerEntries(true, peers, items, null);
        verify(out["share.send.0.clipboard"] === undefined);
        verify(out["share.send.0.image.0"] !== undefined);
    }

    function test_installed_peer_with_nothing_to_share_gets_a_dim_note() {
        var peers = [{ name: "Desk", ip: "10.0.0.5", port: 53317, protocol: "https" }];
        var out = Providers.sharePeerEntries(true, peers, [], null);
        var empty = out["share.send.0.empty"];
        verify(empty);
        compare(empty.kind, "note");
        compare(empty.dim, true);
    }

    function test_installed_multiple_peers_each_get_their_own_index() {
        var peers = [
            { name: "A", ip: "10.0.0.1", port: 53317, protocol: "https" },
            { name: "B", ip: "10.0.0.2", port: 53317, protocol: "https" }
        ];
        var items = [{ id: "t1", kind: "text", text: "hi" }];
        var out = Providers.sharePeerEntries(true, peers, items, null);
        compare(out["share.send.0"].label, "A");
        compare(out["share.send.0.clipboard"].action, "@ipc:localsend.send:0:t1");
        compare(out["share.send.1"].label, "B");
        compare(out["share.send.1.clipboard"].action, "@ipc:localsend.send:1:t1");
    }

    // --- receive status line -----------------------------------------------

    // `dim` stays false on every branch (never used to grey the row): a
    // dim "note" sitting next to "share.send" would be dropped outright by
    // Menu.qml's own live-row filter, which treats a dim note as "this
    // level is empty" rather than "muted status line" (the bug this caught
    // in the VM smoke rig, --share's screenshot showing Send with no
    // Receive row at all until this was fixed).
    function test_receive_status_off_by_config() {
        var out = Providers.sharePeerEntries(true, [], [], { enabled: false, receiving: false, alias: "", dir: "" });
        var node = out["share.receive"];
        compare(node.kind, "note");
        compare(node.dim, false);
        compare(node.desc, "Off (set localsend.receive: true)");
        verify(node.action === undefined);
    }

    function test_receive_status_listening() {
        var out = Providers.sharePeerEntries(true, [], [], { enabled: true, receiving: true, alias: "kyan-laptop", dir: "/home/kyan/Downloads" });
        var node = out["share.receive"];
        compare(node.dim, false);
        compare(node.desc, "Listening as kyan-laptop, saving to /home/kyan/Downloads");
    }

    function test_receive_status_starting_after_a_crash_or_at_boot() {
        var out = Providers.sharePeerEntries(true, [], [], { enabled: true, receiving: false, alias: "kyan-laptop", dir: "/home/kyan/Downloads" });
        var node = out["share.receive"];
        compare(node.dim, false);
        compare(node.desc, "Starting…");
    }

    // Mirrors tst_menu_wallpaper.qml's merge test: nothing under "share" is
    // declared in default-menu.jsonc any more (the whole subtree is
    // dynamic, sharePeerEntries' own header), so this proves buildTree
    // auto-parents dynamically-generated dotted ids at any depth exactly
    // like a statically declared one.
    function test_merged_tree_auto_parents_the_dynamic_subtree() {
        var def = { "share": { label: "Share" } };
        var peers = [{ name: "A", ip: "10.0.0.1", port: 53317, protocol: "https" }];
        var items = [{ id: "t1", kind: "text", text: "hi" }];
        var dynamic = Providers.sharePeerEntries(true, peers, items, { enabled: true, receiving: true, alias: "x", dir: "/d" });
        Object.keys(dynamic).forEach(function (k) { def[k] = dynamic[k]; });
        var tree = Model.buildTree(def, {});
        var share = tree.nodes["share"];
        compare(share.childIds.indexOf("share.receive") >= 0, true);
        compare(share.childIds.indexOf("share.send") >= 0, true);
        var sendFolder = tree.nodes["share.send.0"];
        compare(sendFolder.kind, "submenu");
        compare(sendFolder.childIds.indexOf("share.send.0.clipboard") >= 0, true);
        compare(tree.nodes["share.send.0.clipboard"].kind, "action");
        compare(tree.nodes["share.receive"].kind, "note");
    }

    function test_share_mode_reuses_copy_rows_with_a_distinct_id_namespace() {
        var nodes = Providers.clipboardProvider([
            { id: "a", text: "hello" }
        ], "share");
        compare(nodes.length, 1);
        compare(nodes[0].id, "share.history.a");
        compare(nodes[0].label, "hello");
        compare(nodes[0].kind, "action");
        compare(nodes[0].action, "tmp=$(mktemp --suffix=.txt) && printf '%s' 'hello' > \"$tmp\" && exec localsend_app \"$tmp\"");
    }

    function test_share_mode_preserves_image_rows_shape() {
        var nodes = Providers.clipboardProvider([
            { id: "b", kind: "image", path: "/img/one.png", capturedAt: new Date(2026, 0, 1, 9, 5).getTime() }
        ], "share");
        compare(nodes[0].id, "share.history.b");
        compare(nodes[0].label, "Image");
        compare(nodes[0].desc, "09:05");
        compare(nodes[0].thumbSource, "/img/one.png");
        compare(nodes[0].action, "localsend_app '/img/one.png'");
    }

    function test_default_copy_mode_is_unaffected_by_the_new_parameter() {
        var nodes = Providers.clipboardProvider([{ id: "a", text: "hello" }]);
        compare(nodes[0].id, "clipboard.a");
        compare(nodes[0].action, "@ipc:clipboard.copy:a");
    }

    // The presence-gate itself (default-menu.jsonc's "share" node): the
    // same `when` mechanism system.logout's HYPRLAND_INSTANCE_SIGNATURE
    // guard already proves in tst_menu_model.qml's self-pruning-cascade
    // test, exercised here with the localsend command string. visibleChildren()
    // only ever sees a resolved condResults entry (Menu.qml's own
    // _runCondition fills that in from a real `sh -c` exit code), so this
    // proves the tree wiring honors both outcomes, not the `command -v`
    // shell behavior itself, which is standard POSIX and not FormalShell's
    // to re-verify.
    function test_share_node_when_gate_hides_and_shows_the_whole_subtree() {
        var def = {
            "share": { label: "Share", when: "command -v localsend-cli >/dev/null 2>&1 || command -v localsend_app >/dev/null 2>&1" },
            // kind: "note" matches sharePeerEntries' real output: a leaf
            // with no action/target/provider still needs an explicit kind
            // or buildTree infers "submenu", which visibleChildren only
            // counts as visible when it has visible children of its own.
            "share.receive": { label: "Receive", kind: "note" }
        };
        var tree = Model.buildTree(def, {});
        compare(Model.visibleChildren(tree.nodes, null, { "share": false }).length, 0);
        var visible = Model.visibleChildren(tree.nodes, null, { "share": true });
        compare(visible.length, 1);
        compare(visible[0].id, "share");
    }
}
