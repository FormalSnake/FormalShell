import QtQuick
import QtTest
import "../shell/Tray/model.js" as Tray

TestCase {
    name: "TrayModel"

    readonly property int limit: 4

    function ids(count) {
        var out = [];
        for (var i = 0; i < count; i++)
            out.push("item" + i);
        return out;
    }

    // The arithmetic Tray.qml carried inline before buckets() existed
    // (_pinnedCount / _overflowCount, `_visibleLimit - 1` when overflowing).
    // Reproducing it exactly with both override arrays empty is this
    // module's acceptance criterion, so the reference lives here rather than
    // in a hand-written expectation per case.
    function legacy(list, visibleLimit) {
        var pinnedCount = list.length > visibleLimit ? visibleLimit - 1 : list.length;
        return { visible: list.slice(0, pinnedCount), drawer: list.slice(pinnedCount) };
    }

    // buckets: equivalence with the pre-bucket behavior

    function test_no_overrides_matches_the_old_arithmetic_at_every_count() {
        for (var count = 0; count <= 8; count++) {
            var list = ids(count);
            var b = Tray.buckets(list, [], [], limit);
            var want = legacy(list, limit);
            compare(b.visible.join(","), want.visible.join(","), "visible at count " + count);
            compare(b.drawer.join(","), want.drawer.join(","), "drawer at count " + count);
            compare(b.hidden.length, 0);
        }
    }

    function test_no_overrides_at_the_limit_leaves_no_drawer() {
        var b = Tray.buckets(ids(4), [], [], limit);
        compare(b.visible.join(","), "item0,item1,item2,item3");
        compare(b.drawer.length, 0);
    }

    function test_no_overrides_one_past_the_limit_reserves_the_chevron_slot() {
        var b = Tray.buckets(ids(5), [], [], limit);
        compare(b.visible.join(","), "item0,item1,item2");
        compare(b.drawer.join(","), "item3,item4");
    }

    function test_empty_input_returns_three_empty_buckets() {
        var b = Tray.buckets([], [], [], limit);
        compare(b.visible.length, 0);
        compare(b.drawer.length, 0);
        compare(b.hidden.length, 0);
    }

    // buckets: rule 1, hidden drops out entirely

    function test_hidden_ids_appear_in_neither_visible_nor_drawer() {
        var b = Tray.buckets(ids(5), [], ["item1"], limit);
        compare(b.visible.indexOf("item1"), -1);
        compare(b.drawer.indexOf("item1"), -1);
        compare(b.hidden.join(","), "item1");
    }

    function test_hiding_back_under_the_limit_releases_the_chevron_slot() {
        // Four kept items fit, so nothing overflows and no slot is reserved.
        var b = Tray.buckets(ids(5), [], ["item4"], limit);
        compare(b.visible.join(","), "item0,item1,item2,item3");
        compare(b.drawer.length, 0);
    }

    function test_hiding_everything_leaves_both_render_buckets_empty() {
        var b = Tray.buckets(ids(3), [], ["item0", "item1", "item2"], limit);
        compare(b.visible.length, 0);
        compare(b.drawer.length, 0);
        compare(b.hidden.join(","), "item0,item1,item2");
    }

    // buckets: rule 2, pinned is always visible

    function test_pinned_id_from_the_drawer_moves_into_visible() {
        var b = Tray.buckets(ids(6), ["item5"], [], limit);
        compare(b.visible.indexOf("item5") >= 0, true);
        compare(b.drawer.indexOf("item5"), -1);
    }

    function test_pinned_ids_beyond_the_limit_all_stay_visible() {
        var b = Tray.buckets(ids(6), ["item0", "item1", "item2", "item3", "item4"], [], limit);
        compare(b.visible.join(","), "item0,item1,item2,item3,item4");
        compare(b.drawer.join(","), "item5");
    }

    function test_pinning_takes_the_slots_the_fallback_ordering_would_have() {
        var b = Tray.buckets(ids(6), ["item5"], [], limit);
        compare(b.visible.join(","), "item0,item1,item5");
        compare(b.drawer.join(","), "item2,item3,item4");
    }

    function test_hidden_wins_over_pinned_for_an_id_in_both() {
        var b = Tray.buckets(ids(3), ["item1"], ["item1"], limit);
        compare(b.visible.join(","), "item0,item2");
        compare(b.hidden.join(","), "item1");
    }

    // buckets: ordering

    function test_visible_keeps_incoming_order_rather_than_pins_first() {
        var b = Tray.buckets(ids(6), ["item4"], [], limit);
        compare(b.visible.join(","), "item0,item1,item4");
    }

    function test_drawer_keeps_incoming_order() {
        var b = Tray.buckets(ids(7), [], [], limit);
        compare(b.drawer.join(","), "item3,item4,item5,item6");
    }

    // buckets: malformed input

    function test_undefined_arrays_behave_as_empty() {
        var b = Tray.buckets(ids(5), undefined, undefined, limit);
        compare(b.visible.join(","), "item0,item1,item2");
        compare(b.drawer.join(","), "item3,item4");
    }

    function test_non_array_overrides_are_ignored() {
        var b = Tray.buckets(ids(3), "item0", { id: "item1" }, limit);
        compare(b.visible.join(","), "item0,item1,item2");
        compare(b.hidden.length, 0);
    }

    function test_non_string_entries_are_dropped_from_an_override() {
        var b = Tray.buckets(ids(3), [], [7, null, "item2"], limit);
        compare(b.hidden.join(","), "item2");
        compare(b.visible.join(","), "item0,item1");
    }

    function test_missing_ids_argument_returns_empty_buckets() {
        var b = Tray.buckets(undefined, ["item0"], [], limit);
        compare(b.visible.length, 0);
        compare(b.drawer.length, 0);
        compare(b.hidden.length, 0);
    }

    function test_a_bad_visible_limit_never_throws() {
        var b = Tray.buckets(ids(3), [], [], undefined);
        compare(b.visible.length + b.drawer.length, 3);
    }

    // classify

    function test_classify_defaults_an_unlisted_id_to_drawer() {
        compare(Tray.classify("item0", [], []), "drawer");
    }

    function test_classify_reports_pinned() {
        compare(Tray.classify("item0", ["item0"], []), "pinned");
    }

    function test_classify_reports_hidden() {
        compare(Tray.classify("item0", [], ["item0"]), "hidden");
    }

    function test_classify_prefers_hidden_when_an_id_is_in_both() {
        compare(Tray.classify("item0", ["item0"], ["item0"]), "hidden");
    }

    function test_classify_tolerates_missing_arrays() {
        compare(Tray.classify("item0", undefined, undefined), "drawer");
    }

    // resolveOverride

    function test_resolve_override_prefers_settings_when_present() {
        compare(Tray.resolveOverride(["a"], ["b"]).join(","), "a");
    }

    function test_resolve_override_empty_settings_array_counts_as_present() {
        compare(Tray.resolveOverride([], ["b"]).length, 0);
    }

    function test_resolve_override_falls_back_to_state_when_settings_undefined() {
        compare(Tray.resolveOverride(undefined, ["b"]).join(","), "b");
    }

    function test_resolve_override_falls_back_to_state_when_settings_null() {
        compare(Tray.resolveOverride(null, ["b"]).join(","), "b");
    }
}
