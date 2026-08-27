import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers
import "../shell/Menu/actions.js" as Actions

// The clipssh route's pure half: ~/.clipssh/aliases parsing (clipssh's own
// `name=user@host` format), row building, and the Shift+Enter hint the
// clipboard route's image rows carry. The FileView now lives on
// ClipsshService (the accelerator and the auto-send both resolve an alias
// with no row under a cursor to read one off), and alias resolution itself
// reads Config, so it stays out of this file's reach the same way the rest
// of the QML wiring does.
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
        // Dispatched in-process, never spawned: ClipsshService has to be the
        // thing that runs clipssh, or nothing can report how it went. No
        // shell quoting is involved because no shell string is built: the
        // alias travels as the argument it is.
        compare(rows[0].action, "@ipc:clipssh.send:box");
        // The row fires no toast of its own; the service owns every word the
        // user sees, so a row-level toast would only double the "sending" one.
        compare(rows[0].notifySummary, undefined);
        compare(rows[0].notifyBody, undefined);
    }

    function test_rows_pass_an_awkward_alias_through_verbatim() {
        var rows = Providers.clipsshRows([{ name: "it's", target: "u@h" }]);
        compare(rows[0].action, "@ipc:clipssh.send:it's");
    }

    function test_outcome_success_reads_the_remote_path() {
        // clipssh's own success line, ANSI green included.
        var outcome = Providers.clipsshOutcome(0,
            "\u001b[0;32mUploaded: /tmp/clipboard-1755180000.png\u001b[0m\nPath copied to clipboard - paste it directly\n", "");
        compare(outcome.ok, true);
        compare(outcome.path, "/tmp/clipboard-1755180000.png");
    }

    function test_outcome_success_without_a_readable_path() {
        // Still a completed transfer: the caller says so without inventing
        // a path it never saw.
        var outcome = Providers.clipsshOutcome(0, "", "");
        compare(outcome.ok, true);
        compare(outcome.path, "");
    }

    function test_outcome_failure_reads_clipssh_own_reason() {
        var outcome = Providers.clipsshOutcome(1, "",
            "\u001b[0;31mError:\u001b[0m No image in clipboard. Take a screenshot first\n");
        compare(outcome.ok, false);
        compare(outcome.error, "No image in clipboard. Take a screenshot first");
    }

    function test_outcome_missing_binary() {
        compare(Providers.clipsshOutcome(127, "", "sh: line 1: clipssh: command not found\n").error,
            "clipssh is not installed");
    }

    function test_outcome_failure_falls_back_to_the_last_line() {
        var outcome = Providers.clipsshOutcome(255, "", "ssh: connect to host box.lan port 22: No route to host\n");
        compare(outcome.ok, false);
        compare(outcome.error, "ssh: connect to host box.lan port 22: No route to host");
    }

    function test_outcome_failure_with_nothing_to_go_on() {
        compare(Providers.clipsshOutcome(3, "", "").error, "clipssh exited with code 3");
    }

    // The accelerator's hint (M50). Ungated on aliases existing: with none
    // saved Shift+Enter drills into the route whose empty row above spells
    // out the add command, which beats a hint that isn't there.
    function test_hint_on_a_clipboard_image_row() {
        var labels = Actions.hints({ mode: "menu", clipsshImage: true }).map(function (h) { return h.label; });
        verify(labels.indexOf("Send Over SSH") >= 0);
    }

    function test_no_hint_off_an_image_row() {
        var labels = Actions.hints({ mode: "menu", clipsshImage: false }).map(function (h) { return h.label; });
        compare(labels.indexOf("Send Over SSH"), -1);
    }

    // A row mid-confirmation has already claimed Enter for the confirm, so
    // the alternate is not on offer there either.
    function test_no_hint_while_confirming() {
        var labels = Actions.hints({ mode: "menu", clipsshImage: true, confirming: true })
            .map(function (h) { return h.label; });
        compare(labels.indexOf("Send Over SSH"), -1);
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
