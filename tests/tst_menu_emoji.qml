import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers

// Loads the real vendored dataset (shell/Menu/emoji.json), not a fixture:
// the point is proving the generated file parses and carries the mappings
// the emoji route searches. Reading a file outside the test's own directory
// needs QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner invocations in
// justfile and flake.nix's qml-tests derivation.
TestCase {
    name: "MenuEmoji"

    property var list: []

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../shell/Menu/emoji.json"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        list = Model.parseJsonc(xhr.responseText);
    }

    function test_dataset_loads() {
        verify(list.length > 3000);
        var e = list[0];
        verify(typeof e.ch === "string" && e.ch.length > 0);
        verify(typeof e.name === "string" && e.name.length > 0);
        verify(typeof e.group === "string" && e.group.length > 0);
    }

    function test_known_mapping() {
        var rows = Providers.emojiRows(list, "thumbs up");
        verify(rows.length > 0);
        compare(rows[0].icon, "👍");
        compare(rows[0].label, "THUMBS UP");
        compare(rows[0].kind, "action");
        compare(rows[0].action, "wl-copy -- '👍'");
        // pasteAfter marks the row for Menu.qml's post-close paste hook,
        // the same field and config key a clipboard-history row uses.
        compare(rows[0].pasteAfter, true);
        compare(rows[0].verb, "Paste");
    }

    // clipboard.paste off: the row still copies, it just stops touching the
    // window focus returns to, and says Copy instead of Paste.
    function test_paste_off() {
        var rows = Providers.emojiRows(list, "thumbs up", false);
        compare(rows[0].pasteAfter, false);
        compare(rows[0].verb, "Copy");
        compare(rows[0].action, "wl-copy -- '👍'");
    }

    function test_exact_beats_earlier_substring() {
        // "grinning cat" (Smileys & Emotion) precedes "cat" (Animals &
        // Nature) in file order; the exact-name tier must still win.
        var rows = Providers.emojiRows(list, "cat");
        compare(rows[0].label, "CAT");
        compare(rows[0].icon, "🐈");
    }

    // All four tiers in one query, in order. The ranking is a four-bucket
    // pass rather than a comparator sort (a one-letter query matches most of
    // the dataset), so the tier boundaries and the file order inside a tier
    // are what a regression would break.
    function test_the_four_tiers_rank_in_order() {
        var fixture = [
            { ch: "1", name: "red apple", group: "g" },      // substring
            { ch: "2", name: "cat face", group: "g" },       // prefix
            { ch: "3", name: "cat", group: "g" },            // exact
            { ch: "4", name: "black cat", group: "g" },      // word start
            { ch: "5", name: "cat with tears", group: "g" }  // prefix, later in file order
        ];
        var order = Providers.emojiRows(fixture, "cat").map(function (r) { return r.icon; });
        // exact, then the two prefixes in file order, then word start.
        // "red apple" has no "cat" in it at all and must not appear.
        compare(order, ["3", "2", "5", "4"]);
    }

    function test_trigger_query() {
        compare(Providers.emojiTriggerQuery(":e thumbs"), "thumbs");
        compare(Providers.emojiTriggerQuery(":e "), "");
        compare(Providers.emojiTriggerQuery(":e"), "");
        verify(Providers.emojiTriggerQuery("thumbs") === null);
        verify(Providers.emojiTriggerQuery(":ex") === null);
        verify(Providers.emojiTriggerQuery("") === null);
    }

    // Uncapped since 2026-08-26: the route is a scrolling grid, and the old
    // 40-result ceiling put all but five rows of the set out of reach.
    function test_browse_shows_the_whole_set() {
        compare(Providers.emojiRows(list, "").length, list.length);
        compare(Providers.emojiRows(list, "")[0].label, "GRINNING FACE");
        compare(Providers.emojiRows(list, "zzzznotanemoji").length, 0);
    }

    // A one-letter query matches most of the dataset. Every match has to
    // survive to the grid: the cell the owner is looking for is exactly as
    // likely to be the 400th as the 4th.
    function test_a_broad_query_is_not_truncated() {
        var broad = Providers.emojiRows(list, "a");
        var expected = 0;
        for (var i = 0; i < list.length; i++) {
            if (list[i].name.toLowerCase().indexOf("a") >= 0)
                expected++;
        }
        compare(broad.length, expected);
        verify(broad.length > 40);
    }

    // The memo on `name` must never reach a row: rows are built from the
    // entry's own fields, and a stray `_lcName` on one would be an
    // undeclared field in the model every consumer of a row can see.
    function test_the_search_memo_does_not_leak_into_rows() {
        var rows = Providers.emojiRows(list, "face");
        verify(rows.length > 0);
        verify(rows[0]._lcName === undefined);
    }
}
