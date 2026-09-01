import QtQuick
import QtTest
import "../shell/Menu/frecency.js" as Frecency
import "../shell/Menu/providers.js" as Providers
import "../shell/Menu/search.js" as Search

// The menu's launch-frequency ranking: the scoring itself (count weighted
// by recency decay, zero for anything never launched), the store's
// copy-on-write record(), and — the half that actually matters — how
// little of the ranking it is allowed to touch once it reaches the tree.
// appsProvider only reorders its rows, so frecency decides which of two
// equally-good fuzzy matches leads and nothing more; a stronger match tier
// still wins outright.
TestCase {
    id: testCase

    name: "Frecency"

    readonly property real day: 24 * 60 * 60 * 1000
    readonly property real now: Date.parse("2026-08-06T12:00:00Z")

    function entry(id, name) {
        return { id: id, name: name, icon: "", genericName: "" };
    }

    // What Menu.qml's own _tree binding does: the apps provider's rows,
    // parented under a provider node by the real applyProviders(), which is
    // where their declaration order (and so Search.rank's declIndex) comes
    // from.
    function appsTree(entries, launches) {
        var tree = {
            nodes: {
                apps: {
                    id: "apps",
                    parentId: null,
                    label: "Apps",
                    title: "",
                    aliases: [],
                    kind: "provider",
                    provider: "apps",
                    childIds: []
                }
            }
        };
        return Providers.applyProviders(tree, {
            apps: function () {
                return Providers.appsProvider(entries, null, launches, testCase.now);
            }
        }).nodes;
    }

    // score

    function test_never_launched_entry_scores_zero() {
        compare(Frecency.score([], "firefox", testCase.now), 0);
        compare(Frecency.score([{ id: "mpv", count: 9, lastMs: testCase.now }], "firefox", testCase.now), 0);
    }

    function test_more_launches_scores_higher() {
        var store = [
            { id: "often", count: 12, lastMs: testCase.now },
            { id: "rarely", count: 2, lastMs: testCase.now }
        ];
        verify(Frecency.score(store, "often", testCase.now) > Frecency.score(store, "rarely", testCase.now));
    }

    function test_recent_launch_outranks_older_one_of_the_same_count() {
        var store = [
            { id: "today", count: 3, lastMs: testCase.now },
            { id: "lastmonth", count: 3, lastMs: testCase.now - 30 * testCase.day }
        ];
        verify(Frecency.score(store, "today", testCase.now) > Frecency.score(store, "lastmonth", testCase.now));
    }

    function test_old_pile_of_launches_loses_to_one_recent_launch() {
        var store = [
            { id: "stale", count: 4, lastMs: testCase.now - 60 * testCase.day },
            { id: "fresh", count: 1, lastMs: testCase.now }
        ];
        verify(Frecency.score(store, "fresh", testCase.now) > Frecency.score(store, "stale", testCase.now));
    }

    function test_zero_count_and_absent_record_both_score_zero() {
        compare(Frecency.score([{ id: "never", count: 0, lastMs: testCase.now }], "never", testCase.now), 0);
    }

    // record

    function test_record_appends_a_first_launch() {
        var store = Frecency.record([], "firefox", testCase.now);
        compare(store.length, 1);
        compare(store[0].id, "firefox");
        compare(store[0].count, 1);
        compare(store[0].lastMs, testCase.now);
    }

    function test_record_increments_and_restamps_an_existing_entry() {
        var store = Frecency.record([{ id: "firefox", count: 4, lastMs: testCase.now - 10 * testCase.day }], "firefox", testCase.now);
        compare(store.length, 1);
        compare(store[0].count, 5);
        compare(store[0].lastMs, testCase.now);
    }

    // The JsonAdapter only writes on assignment and QML compares references,
    // so an in-place bump would persist nothing.
    function test_record_never_mutates_the_store_it_was_given() {
        var store = [{ id: "firefox", count: 1, lastMs: 1000 }];
        var next = Frecency.record(store, "firefox", 2000);
        compare(store[0].count, 1);
        compare(store[0].lastMs, 1000);
        compare(next[0].count, 2);
        verify(next !== store);
    }

    function test_record_caps_the_store_by_score() {
        var store = [
            { id: "hot", count: 5, lastMs: testCase.now },
            { id: "ancient", count: 1, lastMs: testCase.now - 200 * testCase.day }
        ];
        var next = Frecency.record(store, "new", testCase.now, 2);
        compare(next.length, 2);
        compare(next[0].id, "hot");
        compare(next[1].id, "new");
    }

    // order

    function test_order_puts_the_most_frecent_first() {
        var items = [{ id: "a" }, { id: "b" }, { id: "c" }];
        var store = [
            { id: "c", count: 6, lastMs: testCase.now },
            { id: "b", count: 1, lastMs: testCase.now }
        ];
        var ordered = Frecency.order(items, store, testCase.now);
        compare(ordered[0].id, "c");
        compare(ordered[1].id, "b");
        compare(ordered[2].id, "a");
    }

    function test_order_is_stable_for_entries_that_tie() {
        var items = [{ id: "a" }, { id: "b" }, { id: "c" }];
        var ordered = Frecency.order(items, [], testCase.now);
        compare(ordered[0].id, "a");
        compare(ordered[1].id, "b");
        compare(ordered[2].id, "c");
    }

    // pullRecorded: the emoji route's per-keystroke reorder. Same contract
    // as order() (recorded ids lead by score, everything else keeps its
    // relative position), reached by decorating only the recorded subset.
    function test_pull_recorded_moves_only_ledger_entries_to_the_front() {
        var items = [{ id: "a" }, { id: "b" }, { id: "c" }, { id: "d" }];
        var store = [{ id: "c", count: 6, lastMs: testCase.now }];
        var ordered = Frecency.pullRecorded(items, store, testCase.now).map(function (i) { return i.id; });
        compare(ordered, ["c", "a", "b", "d"]);
    }

    function test_pull_recorded_leaves_input_order_alone_with_no_ledger() {
        var items = [{ id: "a" }, { id: "b" }, { id: "c" }];
        var ordered = Frecency.pullRecorded(items, [], testCase.now).map(function (i) { return i.id; });
        compare(ordered, ["a", "b", "c"]);
    }

    // Multiple recorded ids still sort by score among themselves, and a
    // stale one that has decayed to zero stays with the untouched rest
    // rather than jumping the queue on presence in the store alone.
    function test_pull_recorded_sorts_multiple_hits_and_drops_decayed_ones() {
        var items = [{ id: "a" }, { id: "b" }, { id: "c" }];
        var year = 365 * 24 * 60 * 60 * 1000;
        var store = [
            { id: "a", count: 1, lastMs: testCase.now },
            { id: "c", count: 9, lastMs: testCase.now },
            { id: "b", count: 50, lastMs: testCase.now - 50 * year }
        ];
        var ordered = Frecency.pullRecorded(items, store, testCase.now).map(function (i) { return i.id; });
        compare(ordered, ["c", "a", "b"]);
    }

    // appsProvider integration

    function test_apps_provider_orders_rows_by_launch_frecency() {
        var rows = Providers.appsProvider([entry("fish", "Fish Shell"), entry("files", "Files")], null, [{ id: "files", count: 3, lastMs: testCase.now }], testCase.now);
        compare(rows[0].id, "apps.files");
        compare(rows[1].id, "apps.fish");
    }

    function test_apps_provider_without_a_store_keeps_desktop_entry_order() {
        var rows = Providers.appsProvider([entry("fish", "Fish Shell"), entry("files", "Files")], null, [], testCase.now);
        compare(rows[0].id, "apps.fish");
        compare(rows[1].id, "apps.files");
    }

    // Search integration: frecency only ever breaks a tie.

    function test_launch_frecency_breaks_a_tie_between_equally_good_matches() {
        var entries = [entry("fish", "Fish Shell"), entry("files", "Files")];
        var cold = Search.rank(appsTree(entries, []), "fi", {});
        compare(cold[0].id, "apps.fish");
        var warm = Search.rank(appsTree(entries, [{ id: "files", count: 3, lastMs: testCase.now }]), "fi", {});
        compare(warm[0].id, "apps.files");
    }

    function test_fuzzy_score_still_dominates_for_a_specific_query() {
        var entries = [entry("recent-files", "Recent Files"), entry("files", "Files")];
        var launches = [{ id: "recent-files", count: 40, lastMs: testCase.now }];
        var ranked = Search.rank(appsTree(entries, launches), "files", {});
        // Exact label match (tier 1000) over a contains match (tier 600) —
        // forty launches cannot buy a tier.
        compare(ranked[0].id, "apps.files");
        compare(ranked[1].id, "apps.recent-files");
    }
}
