// The nix runner's pure half: trigger parsing, `nix search --json` stdout
// parsing, the exit-code to outcome mapping, and row building.

use fs_menu::node::Kind;
use fs_menu::providers::{
    NixResult, NixState, nix_failed_row, nix_indexing_row, nix_no_results_row, nix_rows, nix_search_outcome,
    nix_searching_row, nix_trigger_query, nix_unavailable_row, parse_nix_search,
};
use serde_json::json;

// Same shape the smoke rig's shim echoes: two entries, dotted-prefix keys, one
// version-less field exercised via the empty-string fallback.
fn canned() -> String {
    json!({
        "legacyPackages.x86_64-linux.hello": {
            "description": "A program that produces a familiar, friendly greeting",
            "pname": "hello",
            "version": "2.12.1"
        },
        "legacyPackages.x86_64-linux.python312Packages.requests": {
            "description": "HTTP library",
            "pname": "requests",
            "version": ""
        }
    })
    .to_string()
}

#[test]
fn trigger_query() {
    assert_eq!(nix_trigger_query(":nix hello"), Some("hello"));
    assert_eq!(nix_trigger_query(":nix "), Some(""));
    assert_eq!(nix_trigger_query(":nix"), Some(""));
    assert_eq!(nix_trigger_query("hello"), None);
    assert_eq!(nix_trigger_query(":nixos"), None);
    assert_eq!(nix_trigger_query(""), None);
}

#[test]
fn parse_strips_prefix_keeps_order() {
    let results = parse_nix_search(&canned()).unwrap();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].attr, "hello");
    assert_eq!(results[0].version, "2.12.1");
    assert_eq!(results[0].description, "A program that produces a familiar, friendly greeting");
    // Dotted attrpaths keep everything past the flake/system prefix.
    assert_eq!(results[1].attr, "python312Packages.requests");
    assert_eq!(results[1].version, "");
}

#[test]
fn parse_garbage_is_none_empty_is_list() {
    // Unparseable stdout answers None (SEARCH FAILED's input), distinct from
    // nix's clean zero-hit `{}` (NO RESULTS).
    assert!(parse_nix_search("not json").is_none());
    assert!(parse_nix_search("").is_none());
    assert!(parse_nix_search("null").is_none());
    assert_eq!(parse_nix_search("{}").unwrap().len(), 0);
}

#[test]
fn search_outcome_states() {
    assert_eq!(nix_search_outcome(127, "").state, NixState::Unavailable);
    assert_eq!(nix_search_outcome(1, &canned()).state, NixState::Failed);
    assert_eq!(nix_search_outcome(0, "not json").state, NixState::Failed);
    assert_eq!(nix_search_outcome(0, "{}").state, NixState::Empty);
    let ok = nix_search_outcome(0, &canned());
    assert_eq!(ok.state, NixState::Results);
    assert_eq!(ok.results.len(), 2);
    assert_eq!(ok.results[0].attr, "hello");
    // Failure states never leak partial results.
    assert_eq!(nix_search_outcome(1, &canned()).results.len(), 0);
}

#[test]
fn rows_shape() {
    let rows = nix_rows(&parse_nix_search(&canned()).unwrap());
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].label, "hello 2.12.1");
    assert_eq!(rows[0].desc.as_deref(), Some("A program that produces a familiar, friendly greeting"));
    assert_eq!(rows[0].kind, Kind::Action);
    assert_eq!(rows[0].action.as_deref(), Some("@ipc:nix.run:hello"));
    // Launch acknowledgment fields: the launcher's activation fires
    // notify(summary, body) alongside the spawn.
    assert_eq!(rows[0].notify_summary.as_deref(), Some("NIX RUN"));
    assert_eq!(rows[0].notify_body.as_deref(), Some("hello"));
    // No version: the label is the bare attr.
    assert_eq!(rows[1].label, "python312Packages.requests");
    assert_eq!(rows[1].notify_body.as_deref(), Some("python312Packages.requests"));
}

#[test]
fn rows_skip_unsafe_attrs_and_cap() {
    let unsafe_row = NixResult { attr: "bad'attr".into(), version: "1".into(), description: String::new() };
    assert_eq!(nix_rows(&[unsafe_row]).len(), 0);
    let many: Vec<NixResult> = (0..40)
        .map(|i| NixResult { attr: format!("pkg{i}"), version: "1".into(), description: String::new() })
        .collect();
    assert_eq!(nix_rows(&many).len(), 30);
}

#[test]
fn note_rows() {
    let cases = [
        (nix_unavailable_row(), "nix.unavailable", "Nix is not installed"),
        (nix_indexing_row(), "nix.indexing", "Indexing nixpkgs"),
        (nix_searching_row(), "nix.searching", "Searching"),
        (nix_no_results_row(), "nix.noresults", "No results"),
        (nix_failed_row(), "nix.failed", "Search failed"),
    ];
    for (row, id, label) in cases {
        assert_eq!(row.id, id);
        assert_eq!(row.label, label);
        // kind "note" matches no activation branch: not activatable.
        assert_eq!(row.kind, Kind::Note);
        assert_eq!(row.dim, Some(true));
    }
}
