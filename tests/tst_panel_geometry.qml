import QtQuick
import QtTest
import "../shell/Components/geometry.js" as Geometry

// Panel.qml's frame placement (DESIGN.md §1 "Padding", M48 D3) on each of
// the four bar edges. The tokens are spelled out rather than read off Theme
// so a token change has to be a deliberate edit here too: a 40px bar,
// barMargin 6, screenPadding 12, on a 1920x1080 output.
TestCase {
    id: testCase
    name: "PanelGeometry"

    readonly property real barThickness: 40
    readonly property real barMargin: 6
    readonly property real screenPadding: 12
    readonly property real panelPadding: 12
    readonly property real headerGap: 25
    readonly property real headerHeight: 32

    function insets(position) {
        return {
            top: position === "top" ? testCase.barThickness : 0,
            bottom: position === "bottom" ? testCase.barThickness : 0,
            left: position === "left" ? testCase.barThickness : 0,
            right: position === "right" ? testCase.barThickness : 0
        };
    }

    function frameX(position, anchorX, panelWidth) {
        return Geometry.frameX(position, anchorX, 1920, panelWidth, insets(position),
            testCase.barMargin, testCase.screenPadding);
    }

    function frameY(position, anchorY, frameHeight) {
        return Geometry.frameY(position, anchorY, 1080, frameHeight, insets(position),
            testCase.barMargin, testCase.screenPadding);
    }

    function maxFrame(position, screenHeight) {
        return Geometry.maxFrameHeight(position, screenHeight, insets(position),
            testCase.barMargin, testCase.screenPadding);
    }

    // --- Along the bar -------------------------------------------------

    function test_an_ipc_open_sits_one_screen_padding_from_the_right_edge() {
        compare(frameX("top", -1, 380), 1920 - 380 - 12);
    }

    function test_a_cell_anchored_open_keeps_the_cell_x() {
        compare(frameX("top", 600, 380), 600);
    }

    function test_an_anchor_near_the_right_edge_is_pulled_back_to_the_padding() {
        compare(frameX("top", 1800, 380), 1920 - 380 - 12);
    }

    function test_an_anchor_at_the_left_edge_is_pushed_in_to_the_padding() {
        compare(frameX("top", 0, 380), 12);
    }

    function test_a_frame_wider_than_the_screen_gives_up_the_right_clamp() {
        compare(Geometry.frameX("top", -1, 300, 380, insets("top"), testCase.barMargin,
            testCase.screenPadding), 12);
    }

    // A bottom bar places along x the same way; only the hang changes.
    function test_a_bottom_bar_keeps_the_cell_x_too() {
        compare(frameX("bottom", 600, 380), 600);
    }

    // On a vertical bar the cell's y is what the frame follows.
    function test_a_left_bar_keeps_the_cell_y() {
        compare(frameY("left", 400, 300), 400);
    }

    function test_a_left_bar_ipc_open_sits_one_padding_from_the_bottom_edge() {
        compare(frameY("right", -1, 300), 1080 - 300 - 12);
    }

    function test_a_left_bar_anchor_near_the_bottom_is_pulled_back_up() {
        compare(frameY("left", 1000, 300), 1080 - 300 - 12);
    }

    // --- Off the bar's inner edge --------------------------------------

    function test_a_top_bar_hangs_the_frame_a_margin_under_it() {
        compare(frameY("top", 600, 300), 40 + 6);
    }

    function test_a_bottom_bar_hangs_the_frame_a_margin_over_it() {
        compare(frameY("bottom", 600, 300), 1080 - 40 - 6 - 300);
    }

    function test_a_left_bar_hangs_the_frame_a_margin_to_its_right() {
        compare(frameX("left", 400, 380), 40 + 6);
    }

    function test_a_right_bar_hangs_the_frame_a_margin_to_its_left() {
        compare(frameX("right", 400, 380), 1920 - 40 - 6 - 380);
    }

    // --- The height cap ------------------------------------------------

    function test_the_frame_is_capped_at_the_screen_minus_bar_and_paddings() {
        compare(maxFrame("top", 1080), 1022);
        compare(maxFrame("bottom", 1080), 1022);
    }

    // Beside a vertical bar nothing hangs above or below the frame.
    function test_beside_a_vertical_bar_only_the_paddings_come_off() {
        compare(maxFrame("left", 1080), 1056);
        compare(maxFrame("right", 1080), 1056);
    }

    function test_the_cap_never_goes_negative_on_a_tiny_screen() {
        compare(maxFrame("top", 40), 0);
    }

    function test_content_gets_the_cap_minus_the_frames_own_chrome() {
        compare(Geometry.maxContentHeight(maxFrame("top", 1080), testCase.panelPadding,
            testCase.headerHeight, testCase.headerGap), 941);
    }

    function test_a_short_panel_is_its_own_height() {
        var maxContent = 950;
        compare(Geometry.frameHeight(200, maxContent, testCase.panelPadding,
            testCase.headerHeight, testCase.headerGap), 24 + 32 + 25 + 200);
    }

    function test_a_tall_panel_stops_at_the_cap_and_scrolls() {
        var max = maxFrame("top", 1080);
        var maxContent = Geometry.maxContentHeight(max, testCase.panelPadding,
            testCase.headerHeight, testCase.headerGap);
        compare(Geometry.frameHeight(4000, maxContent, testCase.panelPadding,
            testCase.headerHeight, testCase.headerGap), max);
    }
}
