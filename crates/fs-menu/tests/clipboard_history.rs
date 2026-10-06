use fs_menu::clipboard::history::{
    self as h, Entry, EntryKind, NewEntry, State, add, clear, drop_echo, initial_state, normalize_entry, remove, sanitize,
};
use serde_json::json;

fn entry(id: &str, text: &str) -> NewEntry {
    NewEntry { id: id.into(), text: Some(text.into()), ..NewEntry::default() }
}

fn image(id: &str, path: &str) -> NewEntry {
    NewEntry { id: id.into(), kind: EntryKind::Image, path: Some(path.into()), ..NewEntry::default() }
}

fn texts(s: &State) -> Vec<&str> {
    s.items.iter().map(|i| i.text.as_deref().unwrap_or("")).collect()
}

#[test]
fn initial_state_shape() {
    assert_eq!(initial_state().items.len(), 0);
}

#[test]
fn sanitize_drops_empty_string() {
    assert_eq!(sanitize(""), None);
}

#[test]
fn sanitize_drops_whitespace_only() {
    assert_eq!(sanitize("   \n\t  "), None);
}

#[test]
fn sanitize_keeps_real_text() {
    assert_eq!(sanitize("  hello  ").as_deref(), Some("  hello  "));
}

#[test]
fn sanitize_strips_nul_bytes() {
    assert_eq!(sanitize("\u{0}/tmp/shot.png").as_deref(), Some("/tmp/shot.png"));
}

#[test]
fn sanitize_drops_a_nul_only_capture() {
    assert_eq!(sanitize("\u{0}"), None);
}

// The SplitParser delimiter the capture side lost (see sanitize's comment):
// both halves have to land as the one row.
#[test]
fn add_nul_prefixed_capture_dedupes_with_the_clean_one() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "\u{0}/tmp/shot.png"), 1000).state;
    s = add(&s, &entry("b", "/tmp/shot.png"), 1001).state;
    assert_eq!(s.items.len(), 1);
    assert_eq!(s.items[0].id, "a");
    assert_eq!(s.items[0].text.as_deref(), Some("/tmp/shot.png"));
}

#[test]
fn add_appends_new_entry_to_front() {
    let s = add(&initial_state(), &entry("a", "hello"), 1000).state;
    assert_eq!(s.items.len(), 1);
    assert_eq!(s.items[0].id, "a");
    assert_eq!(s.items[0].kind, EntryKind::Text);
    assert_eq!(s.items[0].text.as_deref(), Some("hello"));
    assert_eq!(s.items[0].captured_at, Some(1000));
}

#[test]
fn add_multiple_entries_newest_first() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "one"), 1000).state;
    s = add(&s, &entry("b", "two"), 1001).state;
    s = add(&s, &entry("c", "three"), 1002).state;
    assert_eq!(texts(&s), ["three", "two", "one"]);
}

#[test]
fn add_dedup_moves_existing_to_front_without_duplicate() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "one"), 1000).state;
    s = add(&s, &entry("b", "two"), 1001).state;
    s = add(&s, &entry("c", "one"), 1002).state; // re-copy of "one"
    assert_eq!(s.items.len(), 2);
    assert_eq!(s.items[0].text.as_deref(), Some("one"));
    assert_eq!(s.items[0].captured_at, Some(1002));
    assert_eq!(s.items[1].text.as_deref(), Some("two"));
}

#[test]
fn add_dedup_preserves_original_id() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "one"), 1000).state;
    s = add(&s, &entry("b", "one"), 2000).state; // dedup should keep id "a"
    assert_eq!(s.items.len(), 1);
    assert_eq!(s.items[0].id, "a");
}

#[test]
fn add_whitespace_only_is_noop() {
    let s = initial_state();
    let result = add(&s, &entry("a", "   "), 1000);
    assert_eq!(result.state, s);
    assert!(result.removed_paths.is_empty());
}

#[test]
fn add_cap_overflow_drops_oldest() {
    let mut s = initial_state();
    for i in 0..300 {
        s = add(&s, &entry(&format!("id{i}"), &format!("text{i}")), 1000 + i).state;
    }
    assert_eq!(s.items.len(), 300);
    assert_eq!(s.items[0].text.as_deref(), Some("text299"));

    let result = add(&s, &entry("id300", "text300"), 1300);
    s = result.state;
    assert_eq!(s.items.len(), 300);
    assert_eq!(s.items[0].text.as_deref(), Some("text300"));
    assert!(result.removed_paths.is_empty()); // evicted entry was text, not image
    assert!(!s.items.iter().any(|i| i.id == "id0")); // oldest evicted
}

#[test]
fn add_image_appends_with_kind_and_defaults_mime() {
    let s = add(&initial_state(), &image("a", "/state/clipboard-images/abc.png"), 1000).state;
    assert_eq!(s.items.len(), 1);
    assert_eq!(s.items[0].kind, EntryKind::Image);
    assert_eq!(s.items[0].path.as_deref(), Some("/state/clipboard-images/abc.png"));
    assert_eq!(s.items[0].mime.as_deref(), Some("image/png"));
    assert_eq!(s.items[0].captured_at, Some(1000));
}

#[test]
fn add_image_without_path_is_noop() {
    let s = initial_state();
    assert_eq!(add(&s, &image("a", ""), 1000).state, s);
}

#[test]
fn add_image_dedups_by_path_moves_to_front_keeps_id() {
    let mut s = initial_state();
    s = add(&s, &image("a", "/img/one.png"), 1000).state;
    s = add(&s, &entry("b", "text between"), 1001).state;
    s = add(&s, &image("c", "/img/one.png"), 1002).state; // re-copy of same path
    assert_eq!(s.items.len(), 2);
    assert_eq!(s.items[0].kind, EntryKind::Image);
    assert_eq!(s.items[0].id, "a"); // original id kept
    assert_eq!(s.items[0].captured_at, Some(1002));
    assert_eq!(s.items[1].text.as_deref(), Some("text between"));
}

// Text dedupes by text, images dedupe by path: a text entry never matches an
// image entry regardless of shared fields.
#[test]
fn add_text_and_image_with_same_id_do_not_collide() {
    let mut s = initial_state();
    s = add(&s, &image("a", "/img/one.png"), 1000).state;
    s = add(&s, &entry("b", "/img/one.png"), 1001).state; // same string, different kind
    assert_eq!(s.items.len(), 2);
}

#[test]
fn add_cap_overflow_reports_evicted_image_paths() {
    let mut s = initial_state();
    for i in 0..300 {
        s = add(&s, &image(&format!("id{i}"), &format!("/img/{i}.png")), 1000 + i).state;
    }
    let result = add(&s, &entry("text300", "final text"), 1300);
    assert_eq!(result.state.items.len(), 300);
    assert_eq!(result.removed_paths, ["/img/0.png"]); // oldest (image) evicted
}

#[test]
fn remove_deletes_by_id() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "one"), 1000).state;
    s = add(&s, &entry("b", "two"), 1001).state;
    let result = remove(&s, "a");
    assert_eq!(result.state.items.len(), 1);
    assert_eq!(result.state.items[0].id, "b");
    assert!(result.removed_paths.is_empty());
}

#[test]
fn remove_image_reports_its_path() {
    let s = add(&initial_state(), &image("a", "/img/one.png"), 1000).state;
    let result = remove(&s, "a");
    assert_eq!(result.state.items.len(), 0);
    assert_eq!(result.removed_paths, ["/img/one.png"]);
}

#[test]
fn remove_unknown_id_is_noop() {
    let s = add(&initial_state(), &entry("a", "one"), 1000).state;
    let result = remove(&s, "missing");
    assert_eq!(result.state, s);
    assert!(result.removed_paths.is_empty());
}

#[test]
fn clear_empties_items() {
    let mut s = initial_state();
    s = add(&s, &entry("a", "one"), 1000).state;
    s = add(&s, &entry("b", "two"), 1001).state;
    assert_eq!(clear(&s).state.items.len(), 0);
}

#[test]
fn clear_reports_every_image_path() {
    let mut s = initial_state();
    s = add(&s, &image("a", "/img/one.png"), 1000).state;
    s = add(&s, &entry("b", "text"), 1001).state;
    s = add(&s, &image("c", "/img/two.png"), 1002).state;
    let result = clear(&s);
    assert_eq!(result.removed_paths.len(), 2);
    assert!(result.removed_paths.contains(&"/img/one.png".to_string()));
    assert!(result.removed_paths.contains(&"/img/two.png".to_string()));
}

#[test]
fn clear_on_empty_is_noop() {
    let s = initial_state();
    let result = clear(&s);
    assert_eq!(result.state, s);
    assert!(result.removed_paths.is_empty());
}

#[test]
fn normalize_entry_legacy_entry_without_kind_reads_as_text() {
    let normalized = normalize_entry(&json!({ "id": "a", "text": "hello", "capturedAt": 1000 })).unwrap();
    assert_eq!(normalized.kind, EntryKind::Text);
    assert_eq!(normalized.text.as_deref(), Some("hello"));
    assert_eq!(normalized.id, "a");
}

#[test]
fn normalize_entry_is_a_noop_for_already_tagged_entries() {
    let img = json!({ "id": "a", "kind": "image", "path": "/img/one.png", "capturedAt": 1000 });
    let normalized = normalize_entry(&img).unwrap();
    assert_eq!(normalized.kind, EntryKind::Image);
    assert_eq!(normalized, Entry { id: "a".into(), kind: EntryKind::Image, path: Some("/img/one.png".into()), captured_at: Some(1000), ..Entry::default() });
    assert_eq!(serde_json::to_value(&normalized).unwrap(), img);
}

// Purity: the reducers take state by reference and the input is intact after.
#[test]
fn purity_add_does_not_mutate_input_state() {
    let s = add(&initial_state(), &entry("a", "one"), 1000).state;
    let before = serde_json::to_string(&s).unwrap();
    add(&s, &entry("b", "two"), 1001);
    assert_eq!(serde_json::to_string(&s).unwrap(), before);
}

#[test]
fn purity_remove_and_clear_do_not_mutate_input_state() {
    let s = add(&initial_state(), &entry("a", "one"), 1000).state;
    let before = serde_json::to_string(&s).unwrap();
    remove(&s, "a");
    clear(&s);
    assert_eq!(serde_json::to_string(&s).unwrap(), before);
}

// drop_echo, the part of the uri-list echo handling that lives in the history
// reducer.
#[test]
fn drop_echo_takes_the_fresh_path_row() {
    let mut s = add(&initial_state(), &entry("a", "older"), 1000).state;
    s = add(&s, &entry("b", "/tmp/a.png\n"), 2000).state;
    s = drop_echo(&s, &["/tmp/a.png", "file:///tmp/a.png"], 2500, 5000);
    assert_eq!(s.items.len(), 1);
    assert_eq!(s.items[0].text.as_deref(), Some("older"));
}

#[test]
fn drop_echo_leaves_other_rows() {
    let mut s = add(&initial_state(), &entry("a", "/tmp/a.png"), 1000).state;
    assert_eq!(drop_echo(&s, &["/tmp/a.png"], 9000, 5000), s);
    s = add(&s, &entry("b", "newer"), 2000).state;
    assert_eq!(drop_echo(&s, &["/tmp/a.png"], 2500, 5000), s);
    assert_eq!(drop_echo(&initial_state(), &["/tmp/a.png"], 0, 5000).items.len(), 0);
}

#[test]
fn max_entries_is_300() {
    assert_eq!(h::MAX_ENTRIES, 300);
}
