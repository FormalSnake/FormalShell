use fs_info::notification_geometry::*;

// 1920x1080 output with a 40px bar, `padding` the screen padding (12) and
// `card_width` popupWidthWide (480) at the default scale.
fn insets(position: &str) -> Insets {
    let edge = |name: &str| if position == name { 40.0 } else { 0.0 };
    Insets {
        top: edge("top"),
        bottom: edge("bottom"),
        left: edge("left"),
        right: edge("right"),
    }
}

fn params(content_height: f64, position: &str) -> CenterParams {
    CenterParams {
        screen_width: 1920.0,
        screen_height: 1080.0,
        padding: 12.0,
        card_width: 480.0,
        content_height,
        insets: insets(position),
    }
}

fn frame(content_height: f64) -> CenterFrame {
    center_frame(&params(content_height, "top"))
}

#[test]
fn it_hangs_a_padding_in_from_the_right_edge() {
    assert_eq!(frame(300.0).x, 1920.0 - 480.0 - 12.0);
}

#[test]
fn it_sits_a_padding_below_the_bar() {
    assert_eq!(frame(300.0).y, 52.0);
}

#[test]
fn a_short_list_takes_its_own_height() {
    let f = frame(300.0);
    assert_eq!(f.height, 300.0);
    assert!(!f.capped);
}

#[test]
fn a_long_list_stops_at_the_bottom_padding() {
    let f = frame(4000.0);
    assert_eq!(f.height, 1016.0);
    assert_eq!(f.available, 1016.0);
    assert!(f.capped);
}

#[test]
fn a_list_that_exactly_fits_is_not_capped() {
    let f = frame(1016.0);
    assert_eq!(f.height, 1016.0);
    assert!(!f.capped);
}

#[test]
fn an_empty_centre_has_no_negative_height() {
    assert_eq!(frame(0.0).height, 0.0);
    assert_eq!(frame(-40.0).height, 0.0);
}

#[test]
fn a_card_wider_than_the_output_clamps_to_the_left_padding() {
    let p = CenterParams {
        screen_width: 320.0,
        ..params(300.0, "top")
    };
    assert_eq!(center_frame(&p).x, 12.0);
}

#[test]
fn an_output_with_no_room_leaves_no_height() {
    let p = CenterParams {
        screen_height: 50.0,
        ..params(300.0, "top")
    };
    let f = center_frame(&p);
    assert_eq!(f.height, 0.0);
    assert!(f.capped);
}

#[test]
fn a_bottom_bar_hangs_the_card_up_from_it() {
    let f = center_frame(&params(300.0, "bottom"));
    assert_eq!(f.y, 1080.0 - 40.0 - 12.0 - 300.0);
    assert_eq!(f.available, 1016.0);
}

#[test]
fn a_right_bar_pushes_the_card_in_from_it() {
    let f = center_frame(&params(300.0, "right"));
    assert_eq!(f.x, 1920.0 - 40.0 - 480.0 - 12.0);
    assert_eq!(f.y, 12.0);
    assert_eq!(f.available, 1056.0);
}

#[test]
fn a_left_bar_leaves_the_right_edge_alone() {
    assert_eq!(
        center_frame(&params(300.0, "left")).x,
        1920.0 - 480.0 - 12.0
    );
    let narrow = CenterParams {
        screen_width: 320.0,
        ..params(300.0, "left")
    };
    assert_eq!(center_frame(&narrow).x, 40.0 + 12.0);
}
