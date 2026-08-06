import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers

// The clipssh route's pure half: ~/.clipssh/aliases parsing (clipssh's own
// `name=user@host` format) and row building. The FileView/reload wiring in
// Menu.qml follows the same optional-file pattern menu.jsonc already
// exercises.
TestCase {
    name: "MenuClipssh"

    function test_parse_aliases() {
        var parsed = Providers.clipsshAliases("box=kyan@box.lan\nvps=root@203.0.113.7\n");
        compare(parsed.length, 2);
        compare(parsed[0].name, "box");
        compare(parsed[0].target, "kyan@box.lan");
        compare(parsed[1].name, "vps");
        compare(parsed[1].target, "root@203.0.113.7");
    }

    function test_parse_skips_malformed_lines() {
        // No '=', empty name, empty target, whitespace name, blank lines —
        // all dropped without poisoning the valid row.
        var text = "\nnot-an-alias\n=nobody@host\nempty=\nbad name=user@host\nok=user@host\n\n";
        var parsed = Providers.clipsshAliases(text);
        compare(parsed.length, 1);
        compare(parsed[0].name, "ok");
        compare(parsed[0].target, "user@host");
    }

    function test_parse_empty_input() {
        compare(Providers.clipsshAliases("").length, 0);
        compare(Providers.clipsshAliases(undefined).length, 0);
    }

    // Targets keep everything after the FIRST '=' — clipssh only bans '='
    // in the name, not the target.
    function test_parse_target_keeps_later_equals() {
        var parsed = Providers.clipsshAliases("odd=user@host=weird");
        compare(parsed.length, 1);
        compare(parsed[0].target, "user@host=weird");
    }

    function test_rows_shape() {
        var rows = Providers.clipsshRows([{ name: "box", target: "kyan@box.lan" }]);
        compare(rows.length, 1);
        compare(rows[0].id, "clipssh.box");
        compare(rows[0].label, "box");
        compare(rows[0].desc, "kyan@box.lan");
        compare(rows[0].kind, "action");
        compare(rows[0].action, "clipssh 'box'");
        compare(rows[0].notifySummary, "CLIPSSH");
        compare(rows[0].notifyBody, "box");
    }

    // Alias names can carry anything but '='/whitespace, so the spawned
    // command must single-quote them — an embedded quote goes through the
    // same '\'' escape clipboardProvider's actions use.
    function test_rows_quote_alias_name() {
        var rows = Providers.clipsshRows([{ name: "it's", target: "u@h" }]);
        compare(rows[0].action, "clipssh 'it'\\''s'");
    }

    function test_rows_empty_is_note() {
        var rows = Providers.clipsshRows([]);
        compare(rows.length, 1);
        compare(rows[0].kind, "note");
        compare(rows[0].dim, true);
        compare(rows[0].label, "NO ALIASES");
        compare(rows[0].desc, "clipssh alias add <name> <user@host>");
    }
}
