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

    // `kw` is optional per entry (CLDR has nothing extra for some, and the
    // generator drops keywords the name already carries), but most of the
    // set has one, and every one it writes is lowercase and pipe separated:
    // the search matches against it raw, with no lowercasing of its own.
    function test_keywords_are_vendored_lowercase() {
        var withKw = 0;
        for (var i = 0; i < list.length; i++) {
            var kw = list[i].kw;
            if (kw === undefined) continue;
            withKw++;
            compare(kw, kw.toLowerCase());
            verify(kw.indexOf("||") < 0);
        }
        verify(withKw > 2000, withKw + " entries carry keywords");
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
    // likely to be the 400th as the 4th. Asserted as containment rather
    // than a count, since keyword hits legitimately add rows no name
    // carries.
    function test_a_broad_query_is_not_truncated() {
        var broad = Providers.emojiRows(list, "a");
        var seen = {};
        for (var i = 0; i < broad.length; i++)
            seen[broad[i].icon] = true;
        var missing = 0, expected = 0;
        for (var j = 0; j < list.length; j++) {
            if (list[j].name.toLowerCase().indexOf("a") < 0) continue;
            expected++;
            if (!seen[list[j].ch]) missing++;
        }
        compare(missing, 0);
        verify(broad.length >= expected);
        verify(broad.length > 40);
    }

    // CLDR's keywords, the thing that makes the route searchable the way
    // macOS's picker is: Unicode's name for 😭 is "loudly crying face", and
    // nothing in it says "sob".
    function test_keywords_find_what_the_name_does_not() {
        compare(Providers.emojiRows(list, "sob")[0].icon, "😭");
        compare(Providers.emojiRows(list, "lmao")[0].icon, "🤣");
        compare(Providers.emojiRows(list, "+1")[0].icon, "👍");
    }

    // The keyword tiers sit below every name tier: a row whose visible name
    // matches always leads one that only matched on data the user can't see.
    function test_a_name_match_still_beats_a_keyword_match() {
        var fixture = [
            { ch: "1", name: "unrelated face", group: "g", kw: "cat" },
            { ch: "2", name: "cat", group: "g" },
            { ch: "3", name: "wildcat", group: "g" },
            { ch: "4", name: "black cat", group: "g" },
            { ch: "5", name: "another face", group: "g", kw: "catnip" }
        ];
        var order = Providers.emojiRows(fixture, "cat").map(function (r) { return r.icon; });
        // name exact, name word start, whole keyword, name substring,
        // keyword word start.
        compare(order, ["2", "4", "1", "3", "5"]);
    }

    // Most-copied first inside a tier, never across one (providers.js's own
    // contract, and the same one appsProvider's frecency has).
    function test_usage_reorders_within_a_tier_only() {
        var fixture = [
            { ch: "1", name: "cat", group: "g" },
            { ch: "2", name: "cat face", group: "g" },
            { ch: "3", name: "cool cat", group: "g" },
            { ch: "4", name: "cat with a hat", group: "g" }
        ];
        var now = Date.now();
        var uses = [
            { id: "emoji.4", count: 9, lastMs: now },
            { id: "emoji.1", count: 1, lastMs: now }
        ];
        var order = Providers.emojiRows(fixture, "cat", true, uses, now).map(function (r) { return r.icon; });
        // "cat with a hat" leads the prefix tier over "cat face" on nine
        // copies, and still does not overtake the exact-name row above it.
        compare(order, ["1", "4", "2", "3"]);
    }

    // The browse grid is the surface the ranking is actually for: an empty
    // query opens on what the user reaches for, not on Unicode file order.
    function test_usage_leads_the_browse_grid() {
        var now = Date.now();
        var uses = [{ id: "emoji.😭", count: 4, lastMs: now }];
        compare(Providers.emojiRows(list, "", true, uses, now)[0].icon, "😭");
        // No ledger, no reordering: a fresh profile browses file order.
        compare(Providers.emojiRows(list, "", true, [], now)[0].label, "GRINNING FACE");
    }

    // A stale ledger entry decays rather than ruling forever: the same
    // half-life the app rows use (frecency.js).
    function test_a_stale_favourite_loses_to_a_recent_one() {
        var fixture = [
            { ch: "1", name: "cat one", group: "g" },
            { ch: "2", name: "cat two", group: "g" }
        ];
        var now = Date.now();
        var year = 365 * 24 * 60 * 60 * 1000;
        var uses = [
            { id: "emoji.1", count: 20, lastMs: now - year },
            { id: "emoji.2", count: 2, lastMs: now }
        ];
        var order = Providers.emojiRows(fixture, "cat", true, uses, now).map(function (r) { return r.icon; });
        compare(order, ["2", "1"]);
    }

    // The memo on `name` must never reach a row: rows are built from the
    // entry's own fields, and a stray `_lcName` on one would be an
    // undeclared field in the model every consumer of a row can see.
    function test_the_search_memo_does_not_leak_into_rows() {
        var rows = Providers.emojiRows(list, "face");
        verify(rows.length > 0);
        verify(rows[0]._lcName === undefined);
        verify(rows[0]._kwIndex === undefined);
        verify(rows[0]._usageId === undefined);
    }
}
