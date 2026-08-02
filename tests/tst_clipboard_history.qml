import QtQuick
import QtTest
import "../shell/Clipboard/history.js" as H

TestCase {
    name: "ClipboardHistory"

    function entry(id, text) {
        return { id: id, text: text };
    }

    function image(id, path, mime) {
        return { id: id, kind: "image", path: path, mime: mime };
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
        s = H.add(s, entry("a", "hello"), 1000).state;
        compare(s.items.length, 1);
        compare(s.items[0].id, "a");
        compare(s.items[0].kind, "text");
        compare(s.items[0].text, "hello");
        compare(s.items[0].capturedAt, 1000);
    }

    function test_add_multiple_entries_newest_first() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        s = H.add(s, entry("b", "two"), 1001).state;
        s = H.add(s, entry("c", "three"), 1002).state;
        var texts = s.items.map(function (i) { return i.text; });
        compare(texts.join(","), "three,two,one");
    }

    function test_add_dedup_moves_existing_to_front_without_duplicate() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        s = H.add(s, entry("b", "two"), 1001).state;
        s = H.add(s, entry("c", "one"), 1002).state; // re-copy of "one"
        compare(s.items.length, 2);
        compare(s.items[0].text, "one");
        compare(s.items[0].capturedAt, 1002);
        compare(s.items[1].text, "two");
    }

    function test_add_dedup_preserves_original_id() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        s = H.add(s, entry("b", "one"), 2000).state; // dedup should keep id "a"
        compare(s.items.length, 1);
        compare(s.items[0].id, "a");
    }

    function test_add_whitespace_only_is_noop() {
        var s = H.initialState();
        var result = H.add(s, entry("a", "   "), 1000);
        compare(result.state, s);
        compare(result.removedPaths.length, 0);
    }

    function test_add_cap_overflow_drops_oldest() {
        var s = H.initialState();
        for (var i = 0; i < 300; i++)
            s = H.add(s, entry("id" + i, "text" + i), 1000 + i).state;
        compare(s.items.length, 300);
        compare(s.items[0].text, "text299");

        var result = H.add(s, entry("id300", "text300"), 1300);
        s = result.state;
        compare(s.items.length, 300);
        compare(s.items[0].text, "text300");
        compare(result.removedPaths.length, 0); // evicted entry was text, not image
        var ids = s.items.map(function (i) { return i.id; });
        verify(ids.indexOf("id0") < 0); // oldest evicted
    }

    function test_add_image_appends_with_kind_and_defaults_mime() {
        var s = H.initialState();
        s = H.add(s, image("a", "/state/clipboard-images/abc.png"), 1000).state;
        compare(s.items.length, 1);
        compare(s.items[0].kind, "image");
        compare(s.items[0].path, "/state/clipboard-images/abc.png");
        compare(s.items[0].mime, "image/png");
        compare(s.items[0].capturedAt, 1000);
    }

    function test_add_image_without_path_is_noop() {
        var s = H.initialState();
        var result = H.add(s, image("a", ""), 1000);
        compare(result.state, s);
    }

    function test_add_image_dedups_by_path_moves_to_front_keeps_id() {
        var s = H.initialState();
        s = H.add(s, image("a", "/img/one.png"), 1000).state;
        s = H.add(s, entry("b", "text between"), 1001).state;
        s = H.add(s, image("c", "/img/one.png"), 1002).state; // re-copy of same path
        compare(s.items.length, 2);
        compare(s.items[0].kind, "image");
        compare(s.items[0].id, "a"); // original id kept
        compare(s.items[0].capturedAt, 1002);
        compare(s.items[1].text, "text between");
    }

    function test_add_text_and_image_with_same_id_do_not_collide() {
        // Text dedupes by text, images dedupe by path — a text entry never
        // matches an image entry regardless of shared fields.
        var s = H.initialState();
        s = H.add(s, image("a", "/img/one.png"), 1000).state;
        s = H.add(s, entry("b", "/img/one.png"), 1001).state; // same string, different kind
        compare(s.items.length, 2);
    }

    function test_add_cap_overflow_reports_evicted_image_paths() {
        var s = H.initialState();
        for (var i = 0; i < 300; i++)
            s = H.add(s, image("id" + i, "/img/" + i + ".png"), 1000 + i).state;
        var result = H.add(s, entry("text300", "final text"), 1300);
        compare(result.state.items.length, 300);
        compare(result.removedPaths.length, 1);
        compare(result.removedPaths[0], "/img/0.png"); // oldest (image) evicted
    }

    function test_remove_deletes_by_id() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        s = H.add(s, entry("b", "two"), 1001).state;
        var result = H.remove(s, "a");
        compare(result.state.items.length, 1);
        compare(result.state.items[0].id, "b");
        compare(result.removedPaths.length, 0);
    }

    function test_remove_image_reports_its_path() {
        var s = H.initialState();
        s = H.add(s, image("a", "/img/one.png"), 1000).state;
        var result = H.remove(s, "a");
        compare(result.state.items.length, 0);
        compare(result.removedPaths.join(","), "/img/one.png");
    }

    function test_remove_unknown_id_is_noop() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        var result = H.remove(s, "missing");
        compare(result.state, s);
        compare(result.removedPaths.length, 0);
    }

    function test_clear_empties_items() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        s = H.add(s, entry("b", "two"), 1001).state;
        var result = H.clear(s);
        compare(result.state.items.length, 0);
    }

    function test_clear_reports_every_image_path() {
        var s = H.initialState();
        s = H.add(s, image("a", "/img/one.png"), 1000).state;
        s = H.add(s, entry("b", "text"), 1001).state;
        s = H.add(s, image("c", "/img/two.png"), 1002).state;
        var result = H.clear(s);
        compare(result.removedPaths.length, 2);
        verify(result.removedPaths.indexOf("/img/one.png") >= 0);
        verify(result.removedPaths.indexOf("/img/two.png") >= 0);
    }

    function test_clear_on_empty_is_noop() {
        var s = H.initialState();
        var result = H.clear(s);
        compare(result.state, s);
        compare(result.removedPaths.length, 0);
    }

    function test_normalizeEntry_legacy_entry_without_kind_reads_as_text() {
        var legacy = { id: "a", text: "hello", capturedAt: 1000 };
        var normalized = H.normalizeEntry(legacy);
        compare(normalized.kind, "text");
        compare(normalized.text, "hello");
        compare(normalized.id, "a");
    }

    function test_normalizeEntry_is_a_noop_for_already_tagged_entries() {
        var img = { id: "a", kind: "image", path: "/img/one.png", capturedAt: 1000 };
        compare(H.normalizeEntry(img), img);
    }

    function test_purity_add_does_not_mutate_input_state() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        var before = JSON.stringify(s);
        H.add(s, entry("b", "two"), 1001);
        compare(JSON.stringify(s), before);
    }

    function test_purity_remove_and_clear_do_not_mutate_input_state() {
        var s = H.initialState();
        s = H.add(s, entry("a", "one"), 1000).state;
        var before = JSON.stringify(s);
        H.remove(s, "a");
        H.clear(s);
        compare(JSON.stringify(s), before);
    }
}
