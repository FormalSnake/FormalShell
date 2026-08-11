import QtQuick
import QtTest
import "../shell/Compositor/keybinds.js" as Keybinds

// The keybinds route's pure half: the niri KDL scanner, the hyprland
// `hyprctl binds -j` mapping, route-local search and row building. The
// FileView/Process wiring in Menu.qml is the same optional-source pattern
// the clipssh and nix routes already use.
TestCase {
    name: "Keybinds"

    // One file carrying every shape the scanner has to survive: a sibling
    // block with its own braces ahead of the binds block, both comment
    // forms between binds, node properties, a quoted argument holding
    // braces and "//", a KDL v2 raw string, and a "/-"-disabled bind. Built
    // as joined lines so QML string escaping never fights KDL quoting.
    readonly property string kdl: [
        "// niri config",
        "layout {",
        "    border {",
        "        width 2",
        "    }",
        "}",
        "",
        "binds {",
        "    Mod+Shift+Slash { show-hotkey-overlay; }",
        '    Mod+T hotkey-overlay-title="Open a Terminal" { spawn "ghostty"; }',
        "    // a disabled thought",
        "    Mod+Q repeat=false { close-window; }",
        "    /* block",
        "       comment */",
        "    Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }",
        '    XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+"; }',
        "    Mod+Ctrl+1 { move-column-to-workspace 1; }",
        '    Mod+N { spawn "sh" "-c" "notify-send {braces} // not-a-comment"; }',
        '    Mod+R { spawn-sh #"echo "raw" > /tmp/keybinds"#; }',
        "    /-Mod+Z { quit; }",
        "}",
        "",
        "input {",
        "    keyboard {",
        "        repeat-delay 600",
        "    }",
        "}"
    ].join("\n")

    readonly property var binds: Keybinds.parseNiriBinds(kdl)

    function _chords(list) {
        return list.map(function (b) { return b.chord; }).join(" ");
    }

    // parseNiriBinds: structure

    function test_finds_binds_block_past_a_sibling_block() {
        compare(binds.length, 8);
        compare(_chords(binds), "Mod+Shift+Slash Mod+T Mod+Q Mod+WheelScrollDown XF86AudioRaiseVolume Mod+Ctrl+1 Mod+N Mod+R");
    }

    function test_parses_chord_mods_and_key() {
        compare(binds[0].chord, "Mod+Shift+Slash");
        compare(binds[0].mods.join("+"), "Mod+Shift");
        compare(binds[0].key, "Slash");
        compare(binds[4].mods.length, 0);
        compare(binds[4].key, "XF86AudioRaiseVolume");
    }

    function test_parses_action_and_args() {
        compare(binds[0].action, "show-hotkey-overlay");
        compare(binds[0].args.length, 0);
        compare(binds[1].action, "spawn");
        compare(binds[1].args.join(" "), "ghostty");
        compare(binds[4].args.length, 4);
        compare(binds[4].args[2], "@DEFAULT_AUDIO_SINK@");
    }

    // A bare KDL number stays the string it was written as: workspace
    // references are opaque ids, not arithmetic.
    function test_parses_bare_unquoted_argument() {
        compare(binds[5].action, "move-column-to-workspace");
        compare(binds[5].args.length, 1);
        compare(binds[5].args[0], "1");
    }

    function test_parses_node_properties() {
        compare(binds[2].props["repeat"], "false");
        compare(binds[3].props["cooldown-ms"], "150");
        compare(binds[4].props["allow-when-locked"], "true");
    }

    function test_hotkey_overlay_title_lifts_to_title() {
        compare(binds[1].title, "Open a Terminal");
        compare(binds[0].title, "");
        compare(binds[7].title, "");
    }

    // The highest-value assertion here: the braces inside the quoted
    // argument must not shift brace depth, and the "//" inside it must not
    // open a comment. Both defeat a line splitter outright.
    function test_quoted_string_may_contain_braces_and_slashes() {
        compare(binds[6].args.length, 3);
        compare(binds[6].args[2], "notify-send {braces} // not-a-comment");
    }

    // KDL v2 raw string: no escape processing, and the inner quotes only
    // end the string when a hash follows.
    function test_raw_string_argument_keeps_its_inner_quotes() {
        compare(binds[7].action, "spawn-sh");
        compare(binds[7].args.length, 1);
        compare(binds[7].args[0], 'echo "raw" > /tmp/keybinds');
    }

    function test_multiline_string_argument() {
        var text = [
            "binds {",
            '    Mod+M { spawn-sh """',
            "line one",
            'line two"""; }',
            "}"
        ].join("\n");
        var parsed = Keybinds.parseNiriBinds(text);
        compare(parsed.length, 1);
        compare(parsed[0].args[0], "line one\nline two");
    }

    function test_comments_are_skipped() {
        // The line comment sits between binds 1 and 2, the block comment
        // between 2 and 3: no phantom bind from either, and the binds
        // bracketing them are intact.
        compare(binds[1].chord, "Mod+T");
        compare(binds[2].chord, "Mod+Q");
        compare(binds[3].chord, "Mod+WheelScrollDown");
    }

    // A "/-" bind showing up as live is a lie the panel must not tell.
    function test_slashdash_drops_the_next_node() {
        compare(binds.filter(function (b) { return b.action === "quit"; }).length, 0);
        compare(binds[6].chord, "Mod+N");
        compare(binds[7].chord, "Mod+R");
    }

    function test_slashdash_disabled_binds_block_is_skipped() {
        var text = [
            "/-binds {",
            "    Mod+X { quit; }",
            "}",
            "binds {",
            "    Mod+Y { close-window; }",
            "}"
        ].join("\n");
        compare(_chords(Keybinds.parseNiriBinds(text)), "Mod+Y");
    }

    // A config being edited right now is malformed most of the time it is
    // read, so every shape returns what it could parse instead of throwing.
    function test_malformed_input_never_throws() {
        compare(Keybinds.parseNiriBinds("").length, 0);
        compare(Keybinds.parseNiriBinds(undefined).length, 0);
        compare(Keybinds.parseNiriBinds("binds {").length, 0);
        compare(Keybinds.parseNiriBinds("not kdl at all {{{").length, 0);
        var partial = Keybinds.parseNiriBinds('binds { Mod+A { spawn "x"');
        compare(partial.length, 1);
        compare(partial[0].chord, "Mod+A");
        compare(partial[0].args[0], "x");
    }

    // describeAction

    function test_describe_action_joins_action_and_args() {
        compare(Keybinds.describeAction(binds[4]), "spawn wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+");
        compare(Keybinds.describeAction(binds[0]), "show-hotkey-overlay");
    }

    // rows

    function test_rows_shape() {
        var rows = Keybinds.rows(binds, "");
        compare(rows.length, 8);
        compare(rows[1].kind, "note");
        // No `dim`: MenuRow keys the label's ink off it, and a real keybind
        // is content, not an unavailable state.
        compare(rows[1].dim, undefined);
        compare(rows[1].icon, "");
        compare(rows[1].label.indexOf("Mod+T"), 0);
        compare(rows[1].desc, "spawn ghostty");
        var ids = rows.map(function (r) { return r.id; });
        compare(ids.filter(function (id, i) { return ids.indexOf(id) === i; }).length, 8);
    }

    // Two binds may legitimately share a chord (hyprland submaps, a config
    // declaring one twice) and the menu keys its node map by id.
    function test_rows_ids_survive_duplicate_chords() {
        var rows = Keybinds.rows([
            { chord: "Mod+A", action: "a", args: [] },
            { chord: "Mod+A", action: "b", args: [] }
        ], "");
        compare(rows[0].id, "keybinds.0.Mod+A");
        compare(rows[1].id, "keybinds.1.Mod+A");
    }

    function test_rows_pad_chords_into_a_column() {
        var rows = Keybinds.rows(binds, "");
        var width = rows[0].label.length;
        // The longest chord in the set, under KEYBINDS_CHORD_PAD_MAX.
        compare(width, "XF86AudioRaiseVolume".length);
        for (var i = 0; i < rows.length; i++) {
            compare(rows[i].label.length, width);
            compare(rows[i].label.trim(), binds[i].chord);
        }
    }

    // search

    function test_search_tiers_and_order() {
        // Every spawn bind, in config declaration order (spawn-sh matches
        // the same action prefix).
        compare(_chords(Keybinds.search(binds, "spawn")), "Mod+T XF86AudioRaiseVolume Mod+N Mod+R");
        compare(Keybinds.search(binds, "Mod+Q")[0].chord, "Mod+Q");
        // "column" reaches move-column-to-workspace across the "-".
        compare(_chords(Keybinds.search(binds, "column")), "Mod+Ctrl+1");
        compare(Keybinds.search(binds, "zzz").length, 0);
        compare(Keybinds.search(binds, "").length, 8);
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

    // parseHyprlandBinds

    readonly property string hyprJson: JSON.stringify([
        { modmask: 64, key: "Q", keycode: 0, dispatcher: "killactive", arg: "", submap: "", description: "", repeat: false, locked: false, release: false },
        { modmask: 65, key: "Return", keycode: 0, dispatcher: "exec", arg: "ghostty", submap: "", description: "Terminal", repeat: false, locked: false, release: false },
        { modmask: 0, key: "", keycode: 24, dispatcher: "exec", arg: "x", submap: "scratch", description: "", repeat: true, locked: true, release: false }
    ])

    function test_hyprland_binds_parse() {
        var parsed = Keybinds.parseHyprlandBinds(hyprJson);
        compare(parsed.length, 3);
        compare(parsed[0].chord, "SUPER+Q");
        compare(parsed[0].mods.join("+"), "SUPER");
        compare(parsed[0].key, "Q");
        compare(parsed[0].action, "killactive");
        compare(parsed[0].args.length, 0);
        // Modifiers read in the order a chord is written, not in bit order.
        compare(parsed[1].chord, "SUPER+SHIFT+Return");
        compare(parsed[1].action, "exec");
        compare(parsed[1].args.join(" "), "ghostty");
        compare(parsed[1].title, "Terminal");
    }

    // An empty `key` means the bind was written against a raw keycode,
    // which is hyprland's own `code:XX` spelling.
    function test_hyprland_keycode_and_props() {
        var parsed = Keybinds.parseHyprlandBinds(hyprJson);
        compare(parsed[2].chord, "code:24");
        compare(parsed[2].props["submap"], "scratch");
        compare(parsed[2].props["locked"], "true");
        compare(parsed[2].props["repeat"], "true");
        compare(parsed[2].props["release"], "false");
    }

    function test_hyprland_malformed_input_never_throws() {
        compare(Keybinds.parseHyprlandBinds("").length, 0);
        compare(Keybinds.parseHyprlandBinds("not json").length, 0);
        compare(Keybinds.parseHyprlandBinds("{}").length, 0);
    }

    // note rows

    function test_note_rows_are_honest() {
        var notes = [Keybinds.noConfigRow(), Keybinds.noBindsRow(), Keybinds.failedRow(), Keybinds.unsupportedRow()];
        compare(notes[0].label, "NO CONFIG");
        compare(notes[1].label, "NO BINDS");
        compare(notes[2].label, "BINDS UNAVAILABLE");
        compare(notes[3].label, "NO BINDS");
        for (var i = 0; i < notes.length; i++) {
            compare(notes[i].kind, "note");
            compare(notes[i].dim, true);
            compare(notes[i].icon, "");
            verify(notes[i].desc !== "");
        }
        // Distinct ids: two of them share a label but never a node key.
        verify(notes[1].id !== notes[3].id);
    }
}
