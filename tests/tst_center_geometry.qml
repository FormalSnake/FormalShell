import QtQuick
import QtTest
import "../shell/Notifications/geometry.js" as Geometry

// M48 D3: the notification centre's card is content-tall until the output
// runs out of room. The tokens are spelled out rather than read off Theme so
// a token change has to be a deliberate edit here too: `padding` is the
// screen padding (12) and `cardWidth` is `popupWidthWide` (480) at the
// default scale, against a 1920x1080 output with a 40px bar.
TestCase {
    name: "CenterGeometry"

    readonly property var tokens: ({
        screenWidth: 1920,
        screenHeight: 1080,
        padding: 12,
        cardWidth: 480
    })

    function insets(position) {
        return {
            top: position === "top" ? 40 : 0,
            bottom: position === "bottom" ? 40 : 0,
            left: position === "left" ? 40 : 0,
            right: position === "right" ? 40 : 0
        };
    }

    function frame(contentHeight, position, overrides) {
        var merged = { contentHeight: contentHeight, insets: insets(position || "top") };
        for (var key in tokens)
            merged[key] = tokens[key];
        for (var extra in (overrides || {}))
            merged[extra] = overrides[extra];
        return Geometry.centerFrame(merged);
    }

    function test_it_hangs_a_padding_in_from_the_right_edge() {
        compare(frame(300).x, 1920 - 480 - 12);
    }

    function test_it_sits_a_padding_below_the_bar() {
        compare(frame(300).y, 52);
    }

    // The claim the surface exists to make: a short history is a short card,
    // not a full-height sheet with empty space under it.
    function test_a_short_list_takes_its_own_height() {
        var f = frame(300);
        compare(f.height, 300);
        compare(f.capped, false);
    }

    // 1080 - 40 - 24 = 1016, the room left between the bar and the padding
    // above the bottom edge.
    function test_a_long_list_stops_at_the_bottom_padding() {
        var f = frame(4000);
        compare(f.height, 1016);
        compare(f.available, 1016);
        compare(f.capped, true);
    }

    // Exactly the available height is not capped: the list has nowhere to
    // scroll, so the flickable must not think it does.
    function test_a_list_that_exactly_fits_is_not_capped() {
        var f = frame(1016);
        compare(f.height, 1016);
        compare(f.capped, false);
    }

    function test_an_empty_centre_has_no_negative_height() {
        compare(frame(0).height, 0);
        compare(frame(-40).height, 0);
    }

    // An output narrower than the card keeps the card on screen from the
    // left padding rather than pushing it off the far side.
    function test_a_card_wider_than_the_output_clamps_to_the_left_padding() {
        compare(frame(300, "top", { screenWidth: 320 }).x, 12);
    }

    // A short output has no room at all under its bar; the card collapses
    // rather than growing upward through it.
    function test_an_output_with_no_room_leaves_no_height() {
        var f = frame(300, "top", { screenHeight: 50 });
        compare(f.height, 0);
        compare(f.capped, true);
    }

    // --- The bar on another edge ---------------------------------------

    // A bottom bar: the card hangs up from it, its bottom edge a padding
    // off the bar, and the same room is left.
    function test_a_bottom_bar_hangs_the_card_up_from_it() {
        var f = frame(300, "bottom");
        compare(f.y, 1080 - 40 - 12 - 300);
        compare(f.available, 1016);
    }

    // A right bar: the card clears it sideways and takes the full height.
    function test_a_right_bar_pushes_the_card_in_from_it() {
        var f = frame(300, "right");
        compare(f.x, 1920 - 40 - 480 - 12);
        compare(f.y, 12);
        compare(f.available, 1056);
    }

    // A left bar changes nothing on the right edge, and an output narrower
    // than the card still clears the bar.
    function test_a_left_bar_leaves_the_right_edge_alone() {
        compare(frame(300, "left").x, 1920 - 480 - 12);
        compare(frame(300, "left", { screenWidth: 320 }).x, 40 + 12);
    }
}
