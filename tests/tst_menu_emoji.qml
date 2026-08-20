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

    function test_trigger_query() {
        compare(Providers.emojiTriggerQuery(":e thumbs"), "thumbs");
        compare(Providers.emojiTriggerQuery(":e "), "");
        compare(Providers.emojiTriggerQuery(":e"), "");
        verify(Providers.emojiTriggerQuery("thumbs") === null);
        verify(Providers.emojiTriggerQuery(":ex") === null);
        verify(Providers.emojiTriggerQuery("") === null);
    }

    function test_browse_and_cap() {
        // Empty query browses the head of the list; results are capped.
        compare(Providers.emojiRows(list, "").length, 40);
        compare(Providers.emojiRows(list, "face").length, 40);
        compare(Providers.emojiRows(list, "zzzznotanemoji").length, 0);
        compare(Providers.emojiRows(list, "")[0].label, "GRINNING FACE");
    }
}
