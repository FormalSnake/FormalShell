import QtQuick
import QtTest
import "../shell/Clipboard/history.js" as H

TestCase {
    name: "ClipboardHistory"

    function entry(id, text) {
        return { id: id, text: text };
    }

    function test_initial_state_shape() {
        var s = H.initialState();
        compare(s.items.length, 0);
    }

    function test_sanitize_drops_empty_string() {
        compare(H.sanitize(""), null);
    }

    function test_sanitize_drops_whitespace_only() {
        compare(H.sanitize("   \n\t  "), null);
    }

    function test_sanitize_keeps_real_text() {
        compare(H.sanitize("  hello  "), "  hello  ");
    }

    function test_add_appends_new_entry_to_front() {
        var s = H.initialState();
        s = H.add(s, entry("a", "hello"), 1000);
        compare(s.items.length, 1);
        compare(s.items[0].id, "a");
        compare(s.items[0].text, "hello");
        compare(s.items[0].capturedAt, 1000);
    }

    function test_add_multiple_entries_newest_first() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        s = H.add(s, entry("b", "two"), 1001);
        s = H.add(s, entry("c", "three"), 1002);
        var texts = s.items.map(function (i) { return i.text; });
        compare(texts.join(","), "three,two,one");
    }

    function test_add_dedup_moves_existing_to_front_without_duplicate() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        s = H.add(s, entry("b", "two"), 1001);
        s = H.add(s, entry("c", "one"), 1002); // re-copy of "one"
        compare(s.items.length, 2);
        compare(s.items[0].text, "one");
        compare(s.items[0].capturedAt, 1002);
        compare(s.items[1].text, "two");
    }

    function test_add_dedup_preserves_original_id() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        s = H.add(s, entry("b", "one"), 2000); // dedup should keep id "a"
        compare(s.items.length, 1);
        compare(s.items[0].id, "a");
    }

    function test_add_whitespace_only_is_noop() {
        var s = H.initialState();
        var updated = H.add(s, entry("a", "   "), 1000);
        compare(updated, s);
    }

    function test_add_cap_overflow_drops_oldest() {
        var s = H.initialState();
        for (var i = 0; i < 300; i++)
            s = H.add(s, entry("id" + i, "text" + i), 1000 + i);
        compare(s.items.length, 300);
        compare(s.items[0].text, "text299");

        s = H.add(s, entry("id300", "text300"), 1300);
        compare(s.items.length, 300);
        compare(s.items[0].text, "text300");
        var ids = s.items.map(function (i) { return i.id; });
        verify(ids.indexOf("id0") < 0); // oldest evicted
    }

    function test_remove_deletes_by_id() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        s = H.add(s, entry("b", "two"), 1001);
        s = H.remove(s, "a");
        compare(s.items.length, 1);
        compare(s.items[0].id, "b");
    }

    function test_remove_unknown_id_is_noop() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        var updated = H.remove(s, "missing");
        compare(updated, s);
    }

    function test_clear_empties_items() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        s = H.add(s, entry("b", "two"), 1001);
        s = H.clear(s);
        compare(s.items.length, 0);
    }

    function test_clear_on_empty_is_noop() {
        var s = H.initialState();
        var updated = H.clear(s);
        compare(updated, s);
    }

    function test_purity_add_does_not_mutate_input_state() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        var before = JSON.stringify(s);
        H.add(s, entry("b", "two"), 1001);
        compare(JSON.stringify(s), before);
    }

    function test_purity_remove_and_clear_do_not_mutate_input_state() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000);
        var before = JSON.stringify(s);
        H.remove(s, "a");
        H.clear(s);
        compare(JSON.stringify(s), before);
    }
}
