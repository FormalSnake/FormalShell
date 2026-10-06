// The camera mirror owns the word "mirror" in the launcher; the display
// panel's output mirroring stays reachable under its own words.

mod common;

use common::*;
use fs_menu::search;

fn first(query: &str, within: Option<&str>) -> String {
    let tree = real_tree();
    search::rank(&tree.nodes, query, &no_conds(), within).first().map(|n| n.id.clone()).unwrap_or_default()
}

#[test]
fn mirror_reaches_the_camera_route_first() {
    assert_eq!(first("mirror", None), "mirror");
}

#[test]
fn camera_and_webcam_reach_the_camera_route() {
    assert_eq!(first("webcam", None), "mirror");
    assert_eq!(first("camera", None), "mirror");
}

// The panels submenu is route-only: its rows are searched from inside it,
// where the Display panel's mirroring words find it.
#[test]
fn display_mirroring_stays_reachable() {
    assert_eq!(first("mirror display", Some("panels")), "panels.display");
    assert_eq!(first("screen mirroring", Some("panels")), "panels.display");
}
