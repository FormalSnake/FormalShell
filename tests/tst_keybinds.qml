import QtQuick
import QtTest
import "../shell/Compositor/keybinds.js" as Keybinds

// The keybinds route's pure half: the `hyprctl binds` table reader,
// route-local search and row building. The Process wiring in Menu.qml is the
// same optional-source pattern the clipssh and nix routes already use.
TestCase {
    name: "Keybinds"

    // Captured verbatim from Hyprland 0.56.0 inside the nested rig
    // (dev/smoke.d/keybinds.sh's own fixture config, dumped by
    // `hyprctl binds`), not invented: the empty-valued fields, the tabs and
    // the `bindd` header for the one bind carrying a description are all
    // hyprland's own spelling. Built as joined lines so QML string escaping
    // never fights the tabs.
    readonly property string bindsText: [
        "bind",
        "\tmodmask: 65",
        "\tsubmap: ",
        "\tkey: slash",
        "\tkeycode: 0",
        "\tcatchall: false",
        "\tdescription: ",
        "\tdispatcher: exec",
        "\targ: hyprctl version",
        "",
        "bindd",
        "\tmodmask: 64",
        "\tsubmap: ",
        "\tkey: T",
        "\tkeycode: 0",
        "\tcatchall: false",
        "\tdescription: Open a Terminal",
        "\tdispatcher: exec",
        "\targ: ghostty",
        "",
        "bind",
        "\tmodmask: 64",
        "\tsubmap: ",
        "\tkey: Q",
        "\tkeycode: 0",
        "\tcatchall: false",
        "\tdescription: ",
        "\tdispatcher: killactive",
        "\targ: ",
        "",
        "bind",
        "\tmodmask: 68",
        "\tsubmap: ",
        "\tkey: 1",
        "\tkeycode: 0",
        "\tcatchall: false",
        "\tdescription: ",
        "\tdispatcher: movetoworkspace",
        "\targ: 1",
        "",
        "bind",
        "\tmodmask: 64",
        "\tsubmap: ",
        "\tkey: N",
        "\tkeycode: 0",
        "\tcatchall: false",
        "\tdescription: ",
        "\tdispatcher: exec",
        "\targ: notify-send {braces} // not-a-comment",
        ""
    ].join("\n")

    readonly property var binds: Keybinds.parseHyprlandBinds(bindsText)

    function _chords(list) {
        return list.map(function (b) { return b.chord; }).join(" ");
    }

    // parseHyprlandBinds: structure

    function test_reads_every_block_in_declaration_order() {
        compare(binds.length, 5);
        compare(_chords(binds), "SUPER+SHIFT+slash SUPER+T SUPER+Q SUPER+CTRL+1 SUPER+N");
    }

    // Modifiers read in the order a chord is conventionally written, not in
    // bit order: 65 is SUPER+SHIFT, never SHIFT+SUPER.
    function test_modmask_expands_in_written_order() {
        compare(binds[0].mods.join("+"), "SUPER+SHIFT");
        compare(binds[0].key, "slash");
        compare(binds[3].mods.join("+"), "SUPER+CTRL");
    }

    function test_dispatcher_and_argument_split() {
        compare(binds[0].action, "exec");
        compare(binds[0].args.join(" "), "hyprctl version");
        // An empty arg is no argument at all, never a "" row.
        compare(binds[2].action, "killactive");
        compare(binds[2].args.length, 0);
        compare(binds[3].args.join(" "), "1");
    }

    // "//" is not a comment in hyprland's config and braces are not a block,
    // so an argument carrying both has to survive the table intact.
    function test_argument_holding_braces_and_slashes_survives() {
        compare(binds[4].args[0], "notify-send {braces} // not-a-comment");
    }

    // `bindd` is a bind carrying a description; every other block header is
    // `bind` and leaves the title empty.
    function test_bindd_carries_its_description_as_the_title() {
        compare(binds[1].title, "Open a Terminal");
        compare(binds[0].title, "");
    }

    function test_props_carry_the_fields_the_table_reports() {
        compare(binds[0].props["submap"], "");
        compare(binds[0].props["catchall"], "false");
    }

    // An empty `key` means the bind was written against a raw keycode, which
    // is hyprland's own `code:XX` spelling.
    function test_keycode_only_bind_reads_as_a_code_chord() {
        var parsed = Keybinds.parseHyprlandBinds([
            "bind",
            "\tmodmask: 0",
            "\tsubmap: scratch",
            "\tkey: ",
            "\tkeycode: 24",
            "\tcatchall: true",
            "\tdescription: ",
            "\tdispatcher: exec",
            "\targ: x"
        ].join("\n"));
        compare(parsed.length, 1);
        compare(parsed[0].chord, "code:24");
        compare(parsed[0].props["submap"], "scratch");
        compare(parsed[0].props["catchall"], "true");
    }

    // A table that stops mid-block still yields the binds above the cut,
    // which is the honest answer for output that was truncated.
    function test_malformed_input_never_throws() {
        compare(Keybinds.parseHyprlandBinds("").length, 0);
        compare(Keybinds.parseHyprlandBinds(undefined).length, 0);
        compare(Keybinds.parseHyprlandBinds("Invalid command").length, 0);
        compare(Keybinds.parseHyprlandBinds("{\"binds\": []}").length, 0);
        var partial = Keybinds.parseHyprlandBinds("bind\n\tmodmask: 64\n\tkey: A\n\tdispatcher: exec");
        compare(partial.length, 1);
        compare(partial[0].chord, "SUPER+A");
    }

    // describeAction

    function test_describe_action_joins_action_and_args() {
        compare(Keybinds.describeAction(binds[0]), "exec hyprctl version");
        compare(Keybinds.describeAction(binds[2]), "killactive");
    }

    // rows

    function test_rows_shape() {
        var rows = Keybinds.rows(binds, "");
        compare(rows.length, 5);
        compare(rows[1].kind, "note");
        // No `dim`: MenuRow keys the label's ink off it, and a real keybind
        // is content, not an unavailable state.
        compare(rows[1].dim, undefined);
        compare(rows[1].icon, "");
        compare(rows[1].label.indexOf("SUPER+T"), 0);
        compare(rows[1].desc, "exec ghostty");
        var ids = rows.map(function (r) { return r.id; });
        compare(ids.filter(function (id, i) { return ids.indexOf(id) === i; }).length, 5);
    }

    // Two binds may legitimately share a chord (two submaps, a config
    // declaring one twice) and the menu keys its node map by id.
    function test_rows_ids_survive_duplicate_chords() {
        var rows = Keybinds.rows([
            { chord: "SUPER+A", action: "a", args: [] },
            { chord: "SUPER+A", action: "b", args: [] }
        ], "");
        compare(rows[0].id, "keybinds.0.SUPER+A");
        compare(rows[1].id, "keybinds.1.SUPER+A");
    }

    function test_rows_pad_chords_into_a_column() {
        var rows = Keybinds.rows(binds, "");
        var width = rows[0].label.length;
        // The longest chord in the set, under KEYBINDS_CHORD_PAD_MAX.
        compare(width, "SUPER+SHIFT+slash".length);
        for (var i = 0; i < rows.length; i++) {
            compare(rows[i].label.length, width);
            compare(rows[i].label.trim(), binds[i].chord);
        }
    }

    // search

    function test_search_tiers_and_order() {
        // Every exec bind, in declaration order.
        compare(_chords(Keybinds.search(binds, "exec")), "SUPER+SHIFT+slash SUPER+T SUPER+N");
        compare(Keybinds.search(binds, "SUPER+Q")[0].chord, "SUPER+Q");
        // "notify" reaches the argument across the space that precedes it.
        compare(_chords(Keybinds.search(binds, "notify")), "SUPER+N");
        // "workspace" only ever appears mid-word, so it lands on the
        // contains tier rather than being dropped.
        compare(_chords(Keybinds.search(binds, "workspace")), "SUPER+CTRL+1");
        compare(Keybinds.search(binds, "zzz").length, 0);
        compare(Keybinds.search(binds, "").length, 5);
    }

    // triggerQuery

    function test_trigger_query() {
        compare(Keybinds.triggerQuery(":k close"), "close");
        compare(Keybinds.triggerQuery(":k "), "");
        compare(Keybinds.triggerQuery(":k"), "");
        compare(Keybinds.triggerQuery("keys"), null);
        compare(Keybinds.triggerQuery(":keys"), null);
        compare(Keybinds.triggerQuery(""), null);
    }

    // note rows

    function test_note_rows_are_honest() {
        var notes = [Keybinds.noBindsRow(), Keybinds.failedRow()];
        compare(notes[0].label, "NO BINDS");
        compare(notes[1].label, "BINDS UNAVAILABLE");
        for (var i = 0; i < notes.length; i++) {
            compare(notes[i].kind, "note");
            compare(notes[i].dim, true);
            compare(notes[i].icon, "");
            verify(notes[i].desc !== "");
        }
        verify(notes[0].id !== notes[1].id);
    }
}
